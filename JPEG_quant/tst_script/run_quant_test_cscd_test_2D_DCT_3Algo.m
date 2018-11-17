function [stats, enc_opts, dec_opts, raw_img, raw_nq_img] = ...
    run_quant_test_cscd_test_2D_DCT_3Algo(img_inp_dir, img_out_dir, img_files,unquant, prll)
  if nargin < 4
    unquant = false;
  end
  if nargin < 5
    prll = false;
  end
  img_out_dir = regexprep(img_out_dir, '*',...
      datestr(now,'yyyymmdd_HHMM'),'once');
%   img_files = {...
%     'barbara.tif', 'boats.tif',...
%     'cameraman.tif', 'foreman.tif', 'house.tif', 'lena256.tif', ...
%     'Monarch.tif', 'Parrots.tif', 'trui1.png' };
  img_files = arrayfun(@(x) {fullfile(img_inp_dir, x{1})}, img_files);
  
    %q_step = [2:4 6 8];
q_step = 3;
  csr = [0.02:0.01:0.05, 0.06:0.02:0.10, 0.15:0.05:0.25];
  
%   enc_opts = struct(...
%     'msrmnt_input_ratio', {num2cell(csr)}, ...
%     'qntzr_wdth_mode', CS_EncParams.Q_WDTH_CSR, ...
%     'qntzr_wdth_mltplr', {num2cell(q_step)}, ...
%     'qntzr_ampl_stddev', 4,...
%     'qntzr_outrange_action', CS_EncImgParams.Q_SAVE,...
%     'msrmnt_mtrx', struct('type', {'SensingMatrixMD_WH' 'SensingMatrixMD_DCT' })...
%     );

%   enc_opts = struct(...
%     'msrmnt_input_ratio', {num2cell(csr)}, ...
%     'qntzr_', struct(...
%     'qntzr_wdth_rng_exp', 6,...
%     'qntzr_wdth_mltplr', {num2cell(q_step),num2cell(q_step/1024)}, ...
%     'qntzr_wdth_mode', {CS_EncParams.Q_WDTH_CSR, CS_EncParams.Q_WDTH_RNG_CSR} ...
%     ),...
%     'msrmnt_mtrx', struct('type', {'MD_WH' 'MD_DCT', 'WH', 'DCT' })...
%     );

%  enc_opts = struct(...
%     'msrmnt_input_ratio', {num2cell(csr)}, ...
%     'msrmnt_mtrx', struct('type', {'MD_WH', 'MD_DCT' },...
%     'nxt', {struct('type', 'LclWH', 'csr', {0.8, 0.9, 1}), []}), ...
%     'qntzr_', struct(...
%     'qntzr_wdth_rng_exp', 6,...
%     'qntzr_wdth_mltplr', {num2cell(q_step),num2cell(q_step*0.0004)}, ...
%     'qntzr_wdth_mode', {CS_EncParams.Q_WDTH_CSR, CS_EncParams.Q_WDTH_RNG_CSR} ...
%     ));

enc_opts = struct(...
    'msrmnt_input_ratio', {num2cell(csr)}, ...
    'msrmnt_mtrx', struct('type', 'MD_DCT','nxt',{[]}),...
    'qntzr_wdth_rng_exp', 6,...
    'qntzr_wdth_mltplr', {num2cell(q_step)}, ...
    'qntzr_wdth_mode', CS_EncParams.Q_WDTH_CSR...
    );

  %dec_opts = struct('alg', {'DAMP', 'GAP_TV', 'NLR_CS', 'SLOPE'});
   dec_opts = struct('alg', {'GAP_TV','DAMP','NLR_CS'});
  
  switch nargout
    case 5
      [stats, enc_opts, dec_opts, raw_img, raw_nq_img] = ...
        test_quant_set(img_files, enc_opts, dec_opts, unquant, 1, img_out_dir, prll);
    case 4
      [stats, enc_opts, dec_opts, raw_img] = ...
        test_quant_set(img_files, enc_opts, dec_opts, unquant, 1, img_out_dir, prll);
    otherwise
      [stats, enc_opts, dec_opts] = ...
        test_quant_set(img_files, enc_opts, dec_opts, unquant, 1, img_out_dir, prll);
  end
end
              
          
  