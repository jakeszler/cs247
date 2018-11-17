function [U, out] = TVAL3_CVS_DT(A,b,p,q,r,opts)
%
% Goal: solve   min sum ||D_i (dt u)||_1
%                  s.t. Au = b
%       to recover video u (usually [0,255]) from encoded b,
%       which is equivalent to solve       min sum ||w_i||
%                                          s.t. D_i (dt u) = w_i
%                                               Au = b
% Here we use 2D total variation on the temporal derivative of u as objective function.
%
% TVAL3 solves the corresponding augmented Lagrangian function:
%
% min_{u,w} sum ( ||w_i||_1 - sigma'(D_i (dt u) - w_i) + beta/2||D_i (dt u) - w_i||_2^2 )
%                   - delta'(Au-b) + mu/2||Au-b||_2^2 ,
%
% by an alternating algorithm:
% i)  while not converge
%     1) Fix w^k, do Gradient Descent to
%            - sigma'(D(dt u)-w^k) - delta'(Au-b) + beta/2||D(dt u)-w^k||^2 + mu/2||Au-b||^2;
%            u^k+1 is determined in the following way:
%         a) compute step length tau > 0 by BB formula
%         b) determine u^k+1 by
%                  u^k+1 = u^k - alpha*g^k,
%            where g^k = -dt'D'sigma - A'delta + beta dt'D'(D(dt u)^k - w^k) + mu A'(Au^k-b),
%            and alpha is determined by Amijo-like nonmonotone line search;
%     2) Given u^k+1, compute w^k+1 by shrinkage
%                 w^k+1 = shrink(D(dt u^k+1)-sigma/beta, 1/beta);
%     end
% ii) update Lagrangian multipliers by
%             sigma^k+1 = sigma^k - beta(D(dt u^k+1) - w^k+1)
%             delta^k+1 = delta^k - mu(Au^k+1 - b).
% iii)accept current u as the initial guess to run the loop again
%
% Inputs:
%       A        : either an matrix representing the measurement or a struct
%                  with 2 function handles:
%                           A(x,1) defines @(x) A*x;
%                           A(x,2) defines @(x) A'*x;
%       b        :  input vector representing the compressed
%                   observation of a grayscale video
%       p, q     :  resolution
%       r        :  # of frames
%       opts     :  structure to restore parameters
%
%
% variables in this code:
%
% lam1 = sum ||wi||_1
% lam2 = ||D(dt u) - w||^2 (at current w).
% lam3 = ||Au - b||^2
% lam4 = sigma'(D(dt u) - w)
% lam5 = delta'(Au - b)
%
%   f  = lam1 + beta/2 lam2 + mu/2 lam3 - lam4 - lam5
%
%   g  = A'(Au - b)
%   g2 = dt'D'(D(dt u) - w) (coefficients beta and mu are not included)
%
%
%
%
%
%
% Written by: Chengbo Li @ Bell Laboratories, Alcatel-Lucent
% Computational and Applied Mathematics department, Rice University
% 06/18/2010




global D Dt T Tt
[D,Dt] = defDDt2;
%[T,Tt] = defTTt;
[T,Tt] = defTTt_NAE;

% problem dimension
n = p*q*r;

% unify implementation of A
if ~isa(A,'function_handle')
    A = @(u,mode) f_handleA(A,u,mode);
end

% get or check opts
opts = TVAL3_CVS_opts(opts);

% mark important constants
mu = opts.mu;
beta = opts.beta;
tol_inn = opts.tol_inn;
tol_out = opts.tol;
gam = opts.gam;

% check if A*A'=I
if norm(A(A(b,2),1)-b,1)/norm(b,1) < 1e-3
    opts.scale_A = false;
end

% check scaling A
if opts.scale_A
    [mu,A,b] = ScaleA(n,mu,A,b,opts.consist_mu);
end

% check scaling b
scl = 1;
if opts.scale_b
    [mu,b,scl] = Scaleb(mu,b,opts.consist_mu);
end

% calculate A'*b
Atb = A(b,2);

% initialize U, beta
muf = mu;
betaf = beta;     % final beta
[U,beta,mu] = init_U(p,q,r,Atb,scl,opts);    % U: p*q
if mu > muf; mu = muf; end
if beta > betaf; beta = betaf; end
muDbeta = mu/beta;
rcdU = U;
nrmrcdU = norm(rcdU(:));
nrmb = norm(b);

% initialize multiplers
sigmax = zeros(p,q,r);                       % sigmax, sigmay: p*q
sigmay = zeros(p,q,r);
delta = zeros(length(b),1);                % delta: m

% initialize dt^T D^T sigma + A^T delta
DtsAtd = zeros(n,1);

% initialize out.errTrue which records the true relative error
if isfield(opts,'Ut')
    Ut = opts.Ut*scl;        %true U, just for computing the error
    nrmUt = norm(Ut(:));
else
    Ut = [];
end
if ~isempty(Ut)
    out.errTrue = norm(U(:) - Ut(:));
end


% prepare for iterations
out.res = [];      % record errors of inner iterations--norm(H-Hp)
out.reer = [];     % record relative errors of outer iterations
out.innstp = [];   % record RelChg of inner iterations
out.itrs = [];     % record # of inner iterations
out.itr = Inf;     % record # of total iterations
out.f = [];        % record values of augmented Lagrangian fnc
out.cnt = [];      % record # of back tracking
out.lam1 = []; out.lam2 = []; out.lam3 = []; out.lam4 = []; out.lam5 = [];
out.tau = []; out.alpha = []; out.C = [];

gp = [];


[Ux,Uy] = D(T(U));                   % Ux, Uy: p*q*z

% first shrinkage step
Wx = max(abs(Ux) - 1/beta, 0).*sign(Ux);
Wy = max(abs(Uy) - 1/beta, 0).*sign(Uy);

lam1 = sum(sum(sum(abs(Wx) + abs(Wy))));

[lam2,lam3,lam4,lam5,f,g2,Au,g] = get_g(U,Ux,Uy,Wx,Wy,...
    lam1,beta,mu,A,b,Atb,sigmax,sigmay,delta);
%lam, f: constant      g2: pq        Au: m         g: pq

% compute gradient
d = g2 + muDbeta*g - DtsAtd;

count = 1; sum_itrs = 0;
Q = 1; C = f;                     % Q, C: costant
out.f = [out.f; f]; out.C = [out.C; C];
out.lam1 = [out.lam1; lam1]; out.lam2 = [out.lam2; lam2]; out.lam3 = [out.lam3; lam3];
out.lam4 = [out.lam4; lam4]; out.lam5 = [out.lam5; lam5];

for ii = 1:opts.maxit
    if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
        fprintf('outer iter = %d, total iter = %d, \n',count,ii);
    end

    % compute tau first
    if ~isempty(gp)
        dg = g - gp;                        % dg: pq
        dg2 = g2 - g2p;                     % dg2: pq
        ss = uup'*uup;                      % ss: constant
        sy = uup'*(dg2 + muDbeta*dg);       % sy: constant
        % sy = uup'*((dg2 + g2) + muDbeta*(dg + g));
        % compute BB step length
        tau = abs(ss/max(sy,eps));               % tau: constant

        fst_itr = false;
    else
        % do Steepest Descent at the 1st ieration
        [dx,dy] = D(T(reshape(d,p,q,r)));                   %dx, dy: p*q*r
        dTDTd = sum(sum(sum(dx.^2 + dy.^2)));               % dTDTd: cosntant
        Ad = A(d,1);                        %Ad: m
        % compute Steepest Descent step length
        tau = abs((d'*d)/(dTDTd + muDbeta*Ad'*Ad));

        % mark the first iteration
        fst_itr = true;
    end

    % keep the previous values
    Up = U; gp = g; g2p = g2; Aup = Au; Uxp = Ux; Uyp = Uy; DtsAtdp =  DtsAtd;

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % ONE-STEP GRADIENT DESCENT %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    taud = tau*d;
    U = U(:) - taud;
    % projected gradient method for nonnegtivity
    if opts.nonneg
        U = max(real(U),0);
    end
    U = reshape(U,p,q,r);
    [Ux,Uy] = D(T(U));

    [lam2,lam3,lam4,lam5,f,g2,Au,g] = get_g(U,Ux,Uy,Wx,Wy,...
        lam1,beta,mu,A,b,Atb,sigmax,sigmay,delta);

    % Nonmonotone Line Search
    alpha = 1;
    du = U - Up;                          % du: p*q
    const = opts.c*beta*(d'*taud);

    % Unew = Up + alpha*(U - Up)
    cnt = 0; flag = true;
    while f > C - alpha*const
        if cnt == 5
            % shrink gam
            gam = opts.rate_gam*gam;

            % give up and take Steepest Descent step
            if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
                disp('    count of back tracking attains 5 ');
            end

            %d = g2p + muDbeta*gp - DtsAtd;
            [dx,dy] = D(T(reshape(d,p,q,r))); 
            dTDTd = sum(sum(sum(dx.^2 + dy.^2))); 
            Ad = A(d,1);
            tau = abs((d'*d)/(dTDTd + muDbeta*Ad'*Ad));
            U = Up(:) - tau*d;
            % projected gradient method for nonnegtivity
            if opts.nonneg
                U = max(real(U),0);
            end
            U = reshape(U,p,q,r);
            [Ux,Uy] = D(T(U));
            Uxbar = Ux - sigmax/beta;
            Uybar = Uy - sigmay/beta;
            Wx = max(abs(Uxbar) - 1/beta, 0).*sign(Uxbar);
            Wy = max(abs(Uybar) - 1/beta, 0).*sign(Uybar);
            lam1 = sum(sum(sum(abs(Wx) + abs(Wy))));
            [lam2,lam3,lam4,lam5,f,g2,Au,g] = get_g(U,Ux,Uy,Wx,Wy,...
                lam1,beta,mu,A,b,Atb,sigmax,sigmay,delta);
            alpha = 0; % remark the failure of back tracking
            break;
        end
        if flag
            dg = g - gp;
            dg2 = g2 - g2p;
            dAu = Au - Aup;                 % dAu: m
            dUx = Ux - Uxp;
            dUy = Uy - Uyp;
            flag = false;
        end
        alpha = alpha*opts.gamma;
        [U,lam2,lam3,lam4,lam5,f,Ux,Uy,Au,g,g2] = update_g(p,q,r,...
            lam1,alpha,beta,mu,Up,du,gp,dg,g2p,dg2,Aup,dAu,Wx,Wy,...
            Uxp,dUx,Uyp,dUy,b,sigmax,sigmay,delta);
        cnt = cnt + 1;
    end

    % if back tracking is succeceful, then recompute
    if alpha ~= 0
        Uxbar = Ux - sigmax/beta;
        Uybar = Uy - sigmay/beta;
        Wx = max(abs(Uxbar) - 1/beta, 0).*sign(Uxbar);
        Wy = max(abs(Uybar) - 1/beta, 0).*sign(Uybar);

        % update parameters related to Wx, Wy
        [lam1,lam2,lam4,f,g2] = update_W(beta,...
            Wx,Wy,Ux,Uy,sigmax,sigmay,lam1,lam2,lam4,f);
    end

    % update reference value
    Qp = Q; Q = gam*Qp + 1; C = (gam*Qp*C + f)/Q;
    uup = U - Up; uup = uup(:);           % uup: pq
    nrmuup = norm(uup);                   % nrmuup: constant

    out.res = [out.res; nrmuup];
    out.f = [out.f; f]; out.C = [out.C; C]; out.cnt = [out.cnt;cnt];
    out.lam1 = [out.lam1; lam1]; out.lam2 = [out.lam2; lam2]; out.lam3 = [out.lam3; lam3];
    out.lam4 = [out.lam4; lam4]; out.lam5 = [out.lam5; lam5];
    out.tau = [out.tau; tau]; out.alpha = [out.alpha; alpha];

    if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
        fprintf('       ||D(T(U))-W|| = %5.3f, ||Au-f||/||f|| = %5.3f, ',...
            sqrt(lam2), sqrt(lam3)/nrmb);
    end

    if ~isempty(Ut)
        errT = norm(U(:) - Ut(:));
        out.errTrue = [out.errTrue; errT];
        if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
            fprintf('  ||Utrue-U||(/||Utrue||) = %5.3f(%5.3f%%), ',errT, 100*errT/nrmUt);
        end
    end

    % recompute gradient
    d = g2 + muDbeta*g - DtsAtd;

    % compute relative change or optimality gap
    if opts.StpCr == 1           % relative change
        nrmup = norm(Up(:));
        RelChg = nrmuup/nrmup;
        if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
            fprintf('    ||Uprvs-U||/||Uprvs|| = %5.3f; \n', RelChg);
        end
    else                         % d(L_A)/du
        RelChg = norm(d);
        if (opts.disp > 0) && (mod(ii,opts.disp) == 0)
            fprintf('    optimality gap = %5.3f; \n', RelChg);
        end
    end
    out.innstp = [out.innstp; RelChg];

    if (RelChg < tol_inn || ii-sum_itrs >= opts.maxin)
        count = count + 1;
        if opts.StpCr == 1       % relative change
            RelChgOut = norm(U(:)-rcdU(:))/nrmrcdU;
            rcdU = U;
            nrmrcdU = norm(rcdU(:));
        else                     % ||Au - f||/||f||
            RelChgOut = sqrt(lam3)/nrmb;
        end
        out.reer = [out.reer; RelChgOut];

        if isempty(out.itrs)
            out.itrs = ii;
        else
            out.itrs = [out.itrs; ii - sum(out.itrs)];
        end
        sum_itrs = sum(out.itrs);

        % stop if already reached final multipliers
        if RelChgOut < tol_out || count > opts.maxcnt
            if opts.isreal
                U = real(U);
            end
            if exist('scl','var')
                U = U/scl;
            end
            out.itr = ii;
            fprintf('Number of total iterations is %d. \n',out.itr);
            return
        end

        % update multipliers
        [sigmax,sigmay,delta,lam4,lam5,f] = update_mlp(beta,mu, ...
            Wx,Wy,Ux,Uy,Au,b,sigmax,sigmay,delta,lam4,lam5,f);
        
        % update penality parameters for continuation scheme
        beta0 = beta;
        beta = beta*opts.rate_ctn;
        mu = mu*opts.rate_ctn;
        if beta > betaf; beta = betaf; end
        if mu > muf; mu = muf; end
        muDbeta = mu/beta;
        
        % update function value, gradient, and relavent constant
        f = lam1 + beta/2*lam2 + mu/2*lam3 - lam4 - lam5;
        DtsAtd = -(beta0/beta)*d;     % DtsAtd should be divded by new beta instead of the old one for consistency!
        d = g2 + muDbeta*g - DtsAtd;

        %initialize the constants
        gp = [];
        gam = opts.gam; Q = 1; C = f;
    end

end

if opts.isreal
    U = real(U);
end
if exist('scl','var')
    fprintf('Attain the maximum of iterations %d. \n',opts.maxit);
    U = U/scl;
end




function [lam2,lam3,lam4,lam5,f,g2,Au,g] = get_g(U,Ux,Uy,Wx,Wy,...
    lam1,beta,mu,A,b,Atb,sigmax,sigmay,delta)
global Dt Tt

% A*u
Au = A(U(:),1);

% g
g = A(Au,2) - Atb;



% lam2
Vx = Ux - Wx;
Vy = Uy - Wy;
lam2 = sum(sum(sum(Vx.*Vx + Vy.*Vy)));


% g2 = D'(Du-w)
G2 = Tt(Dt(Vx,Vy));
g2 = G2(:);

% lam3
Aub = Au-b;
lam3 = norm(Aub)^2;

%lam4
lam4 = sum(sum(sum(sigmax.*Vx + sigmay.*Vy)));

%lam5
lam5 = delta'*Aub;

% f
f = lam1 + beta/2*lam2 + mu/2*lam3 - lam4 - lam5;



function [U,lam2,lam3,lam4,lam5,f,Ux,Uy,Au,g,g2] = update_g(p,q,r,lam1,...
    alpha,beta,mu,Up,du,gp,dg,g2p,dg2,Aup,dAu,Wx,Wy,Uxp,dUx,Uyp,dUy,...
    b,sigmax,sigmay,delta)

g = gp + alpha*dg;
g2 = g2p + alpha*dg2;
U = Up + alpha*reshape(du,p,q,r);
Au = Aup + alpha*dAu;
Ux = Uxp + alpha*dUx;
Uy = Uyp + alpha*dUy;

Vx = Ux - Wx;
Vy = Uy - Wy;
lam2 = sum(sum(sum(Vx.*Vx + Vy.*Vy)));
Aub = Au-b;
lam3 = norm(Aub)^2;
lam4 = sum(sum(sum(sigmax.*Vx + sigmay.*Vy)));
lam5 = delta'*Aub;
f = lam1 + beta/2*lam2 + mu/2*lam3 - lam4 - lam5;



function [lam1,lam2,lam4,f,g2] = update_W(beta,...
    Wx,Wy,Ux,Uy,sigmax,sigmay,lam1,lam2,lam4,f)
global Dt Tt

% update parameters because Wx, Wy were updated
tmpf = f -lam1 - beta/2*lam2 + lam4;
lam1 = sum(sum(sum(abs(Wx) + abs(Wy))));
Vx = Ux - Wx;
Vy = Uy - Wy;
G2 = Tt(Dt(Vx,Vy));
g2 = G2(:);
lam2 = sum(sum(sum(Vx.*Vx + Vy.*Vy)));
lam4 = sum(sum(sum(sigmax.*Vx + sigmay.*Vy)));
f = tmpf +lam1 + beta/2*lam2 - lam4;



function [sigmax,sigmay,delta,lam4,lam5,f] = update_mlp(beta,mu, ...
    Wx,Wy,Ux,Uy,Au,b,sigmax,sigmay,delta,lam4,lam5,f)

Vx = Ux - Wx;
Vy = Uy - Wy;
sigmax = sigmax - beta*Vx;
sigmay = sigmay - beta*Vy;
Aub = Au-b;
delta = delta - mu*Aub;

tmpf = f + lam4 + lam5;
lam4 = sum(sum(sum(sigmax.*Vx + sigmay.*Vy)));
lam5 = delta'*Aub;
f = tmpf - lam4 - lam5;




function [U,beta,mu] = init_U(p,q,r,Atb,scl,opts)

% initialize beta
if isfield(opts,'beta0') && isfield(opts,'mu0')
    beta = opts.beta0;
    mu = opts.mu0;
else
    error('Initial mu or beta is not provided.');
end

% initialize U
[mm,nn,rr] = size(opts.init);
if max([mm,nn,rr]) == 1
    switch opts.init
        case 0, U = zeros(p,q,r);
        case 1, U = reshape(Atb,p,q,r);
    end
else
    if mm ~= p || nn ~= q || rr ~= r
        fprintf('Input initial guess has incompatible size! Switch to the default initial guess. \n');
        U = reshape(Atb,p,q,r);
    else
        U = opts.init*scl;
    end
end
