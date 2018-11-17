% This scripts generates measurements using DCT with local randomization
% (no quantization).
[mpath,~,~] = fileparts(mfilename('fullpath'));
cd(mpath)
cd ..
cd ..
cd test_data
enc_opts = struct(...
    'n_frames',60,...
    'process_color',false,...
    'random',struct('seed',1000),...
    'blk_size','&[72 88 12]',...
    'msrmnt_mtrx',{{...
    struct('type','SensingMatrixLclDCT', 'args',struct()),...
    struct('type','SensingMatrixDCT', 'args',struct()),...
    struct('type','SensingMatrixNrDCT', 'args',struct())...
    }},...
    'msrmnt_input_ratio', 1.0,...
    'qntzr_wdth_mltplr',0,...
    'qntzr_ampl_stddev',10000);
anls_opts = [];
dec_opts = [];
proc_opts = struct('output_id','msrs_*','case_id','<Mt>_<Bs>', ...
    'par_cases', length(enc_opts.msrmnt_mtrx));
files_def = '<foreman_news_io.json';
sml_io =  CSVidCodec.doSimulation(enc_opts,anls_opts,dec_opts,files_def, proc_opts);