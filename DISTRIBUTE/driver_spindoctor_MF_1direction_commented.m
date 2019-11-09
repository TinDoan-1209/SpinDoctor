%%%% The DISTRIBUTE folder contains a commented general purpose driver 
%%%% called driver_spindoctor_MF_1direction_commented.m. 
%%%% It is highly recommended to read this driver to understand the workflow 
%%%% of SpinDoctor and the Matrix Formalism Module. 
%%%% driver_spindoctor_MF_commented.m does not use saved simulation data, 
%%%% all simulations are run from scratch.
%%%% The user is advised to read the latest version 
%%%% from \url{https://github.com/jingrebeccali/SpinDoctor} 
clear all;
close all;
restoredefaultpath;

%%%% User needs to choose to see some of the typical plots or not.
DO_PLOTS = true;
%%%% User needs to choose to the minimum length scale of interest
%%%% This controls the upper limit of eigenvalue interval to solve for
%%%% Laplace eigenvalues.
LSCALE_MIN = 4;
%%%% When there are too many eigenvalues in the requested eigenvalue
%%%% interval, Matlab takes a long time to converge.  So it is better to
%%%% break the requested eigenvalue interval into many subintervals so that
%%%% there are no more than 10 or so eigenvalues in each interval.  
%%%% The User should specify how many subintervals to break the requested
%%%% eigenvalue interval into.  Values between 1 and 100 can be tried here.
NUM_EIGINTERVALS = 30;

%%%% User needs to define the directory where the 3 user provided input files are kept.
user_inputfiles_dir = 'params_files/params_spindoctor_MF_1direction_commented';

%%%% User needs to define the names of the 3 user provided input files
%%%% found in user_inputfiles_dir
fname_params_cells = 'params_cells_neuron.in';
fname_params_simul_domain  = 'params_simul_domain_neuron.in';
fname_params_simul_experi = 'params_simul_experi_neuron.in';

%%%% We add the path to the directory of the 3 user provided input files.
eval(['addpath ', user_inputfiles_dir]);

%%%% We add the path to the top level source code directory.
addpath SRC
%%%% We add the path to the deeper level source code directories.
%%%% We note the functions that need to be called in a typical simulation
%%%% situation are contained in the top level directory 'SRC'.
%%%% The less often used functions are kept in the deeper levels.
addpath SRC/PDE SRC/DMRI SRC/FEM SRC/GEOM SRC/TETGEN

%%%% We read the params_cells input file and create the geometrical configuration
%%%% In the first line of the params_cells input file, we expect a number
%%%% between 1 and 3;
%%%% 1 = ellipsoids, 2 = cylinders, 3 = neuron from msh file;
[params_cells,fname_cells] = create_geom(fname_params_cells);

%%%% We read the params_simul_domain input file;
[params_domain_geom,params_domain_pde,params_domain_femesh] ...
    = read_params_simul_domain(fname_params_simul_domain);

%%%% We set up the PDE model in the geometrical compartments.
[DIFF_cmpts,kappa_bdys,IC_cmpts,OUT_cmpts_index,ECS_cmpts_index,IN_cmpts_index,Ncmpt,Nboundary] ...
    = PREPARE_PDE(params_cells.ncell,params_cells.cell_shape,params_domain_geom,params_domain_pde);

%%%% We make a directory to store the finite elements mesh for this simulation;
save_meshdir_path = [fname_cells,'_dir'];
tf = isfolder(save_meshdir_path);
if (~tf)
    call_cmd = ['mkdir ',save_meshdir_path];
    disp(call_cmd);
    eval([call_cmd]);
end

%%%% We use an existing finite elements mesh or we create a new finite
%%%% elements mesh.
%%%% The name of the finite elements mesh is stored in the string fname_tetgen_femesh
ns = regexp(fname_cells,'/');
save_mesh_name = [fname_cells(ns(end)+1:end),'Htetgen',num2str(params_domain_femesh.Htetgen),'msh'];
fname_tetgen = [save_meshdir_path,'/',save_mesh_name];
fname_tmp = [fname_tetgen,'.1'];
tf = isfile([fname_tmp,'.node']);
if (tf)
    fname_tetgen_femesh = fname_tmp;
else
    [fname_tetgen_femesh] = ...
        create_femesh_fromcells(params_cells,fname_cells,params_domain_geom,params_domain_femesh,fname_tetgen);
end

%%%% We do not deform the finite elements mesh if in the Neuron module.
%%%% We do deform the finite elements mesh if in SpinDoctor White Matter
%%%% mode.
%%%% The finite elements mesh is stored in mymesh
if (params_cells.cell_shape == 3)
    params_cells.para_deform = [0,0]';
    [mymesh,cmpts_bdys_mat] = read_tetgen(fname_tetgen_femesh,params_cells.para_deform,Ncmpt,Nboundary);
else
    [mymesh,cmpts_bdys_mat] = read_tetgen(fname_tetgen_femesh,params_cells.para_deform,Ncmpt,Nboundary);
end

%%%% We plot the finite elements mesh
if (DO_PLOTS)
    PLOT_FEMESH(mymesh,OUT_cmpts_index,ECS_cmpts_index,IN_cmpts_index);
end

%%%% We read the params_simul_experi input file;
[experi_common,experi_hadc,experi_btpde] ...
    = read_params_simul_experi(fname_params_simul_experi);

%%%% We get the volume and the surface area quantities from the mesh
[VOL_cmpts,SA_cmpts,SAu_cmpts,VOL_allcmpts,VF_cmpts,SoV_cmpts] ...
    = GET_VOL_SA(mymesh,experi_common.gdir);

%%%% Instead of using 0 as the minimum of the eigenvalue interval we use
%%%% -infinity to make sure we get 0 as an output eigenvalue.
EigLim_min(1:Ncmpt) = -Inf;
%%%% The upper bound of the eigenvalue interval is determined by
%%%% LSCALE_MIN, which is the minimum length scale of interest.
%%%% This minimum length gives the upper bound of the eigenvalue interval
%%%% by using the formula that links the eigenvalues of the line segment
%%%% and the wavelength of the eigenfunctions on the line segment.
EigLim(1:Ncmpt) = DIFF_cmpts.*(pi^2./(LSCALE_MIN.^2));

%%%% Breaking the requested eigenvalue interval into a number of
%%%% subintervals so that Matlab matrix eigenvalue problem can converge 
%%%% quickly.  The optimal choice
%%%% is when there are not more than 10 or 20 eigenvalues in each
%%%% subinterval.
EigIntervals(1:Ncmpt) = NUM_EIGINTERVALS;

for icmpt = 1:Ncmpt
    [EIG_value_cmpts{icmpt},EIG_proj_cmpts{icmpt},EIG_func_cmpts{icmpt},ctime_laplace(1,icmpt)]...
        = LAPLACE_EIG(mymesh.Pts_cmpt_reorder{icmpt},mymesh.Ele_cmpt_reorder{icmpt},...
        DIFF_cmpts(icmpt),VOL_cmpts(icmpt),EigLim(icmpt),EigLim_min(icmpt),EigIntervals(icmpt));   
end

%%%% Converting eigenvalues into a length scale according to the
%%%% eigenvalues of the line segment and their connection to the wavelength
%%% of the Laplace eigenfunctions on the line segment.
[EIG_length_cmpts] = MF_EIG_TO_LENGTH(EIG_value_cmpts,DIFF_cmpts);

experi_mf = experi_btpde;
nb = size(experi_mf.bvalues,2);
nexperi = size(experi_mf.bvalues,1);

%%%% Computing the JN value that relates the eigenmodes to their
%%%% contribution to the Matrix Formalism signal for a diffusion-encoding
%%%% sequence.  Note, only PGSE is implemented at this point.
[MF_JN_cmpts] = MF_JN(EIG_value_cmpts,DIFF_cmpts,experi_mf);

% We compute the Matrix Formalism effective diffusion tensor
[DTENSOR_cmpts,DTENSOR_allcmpts] = MF_DTENSOR(VOL_cmpts,...
    IC_cmpts,EIG_value_cmpts,EIG_proj_cmpts,DIFF_cmpts,MF_JN_cmpts);

if (DO_PLOTS ~= 0)   
    %%%% We plot the Matrix Formalism effective diffusion tensor
    PLOT_DTENSOR(DTENSOR_cmpts,DTENSOR_allcmpts,DIFF_cmpts);
    cmpts_use = 1;
    %%%% We plot the eigenfunction index by nindex
    for nindex = 2
        diffdir = EIG_proj_cmpts{cmpts_use}(:,nindex);
        title_str = ['EigFun, l_s = ', num2str(EIG_length_cmpts{1}(nindex))...
                ', a_{1n} = [',num2str(diffdir'),']^T'];    
        PLOT_EIGENFUNCTION(mymesh,EIG_func_cmpts,OUT_cmpts_index,ECS_cmpts_index,IN_cmpts_index,...
            nindex,title_str);
    end
end

%%%% We run the simulation for one diffusion-encoding direction
if (experi_common.ngdir_total == 1)
    if (~isempty(experi_btpde))
        %%%% We solve the BTPDE 
        [SOL,SIG_BTPDE_cmpts,SIG_BTPDE_allcmpts,difftime,ctime_btpde] ...
            = BTPDE(experi_btpde,mymesh,DIFF_cmpts,kappa_bdys,IC_cmpts,false);
        %%%% We fit the ADC of the signal
        [ADC_BTPDE_cmpts,ADC_BTPDE_allcmpts,ADC_allcmpts_S0] ...
            = FIT_SIGNAL(SIG_BTPDE_cmpts,SIG_BTPDE_allcmpts,experi_btpde.bvalues);
        %%%% We obtain the signal of free diffusion
        [Sig_free,ADC_free_allcmpts] = ADCFREE(experi_btpde.bvalues,DIFF_cmpts,VOL_cmpts,IC_cmpts);
        
        %%%% We compute the Matrix Formalism signal
        [SIG_MF_cmpts,SIG_MF_allcmpts,ctime_mf] ...
            = SIG_MF(experi_mf,VOL_cmpts,IC_cmpts,EIG_value_cmpts,EIG_proj_cmpts);
        %%%% We fit the ADC of the signal
        [ADC_MF_cmpts,ADC_MF_allcmpts,ADC_MF_allcmpts_S0] ...
            = FIT_SIGNAL(SIG_MF_cmpts,SIG_MF_allcmpts,experi_mf.bvalues);       
        
        %%%% We compute the Matrix Formalism Gaussian Approximation signal
        [SIG_MFGA_cmpts,SIG_MFGA_allcmpts] ...
            = SIG_MFGA(experi_mf,VOL_cmpts,IC_cmpts,DTENSOR_cmpts);
        %%%% We fit the ADC of the signal
        [ADC_MFGA_cmpts,ADC_MFGA_allcmpts,ADC_MFGA_allcmpts_S0] ...
            = FIT_SIGNAL(SIG_MFGA_cmpts,SIG_MFGA_allcmpts,experi_mf.bvalues);        
        
        % We plot the BTPDE, MF and MFGA signals
        if (DO_PLOTS ~= 0)
            PLOT_SIGNAL(experi_btpde.bvalues,SIG_BTPDE_allcmpts,Sig_free,ADC_allcmpts_S0,ADC_BTPDE_allcmpts,'BTPDE signal');
            PLOT_SIGNAL(experi_mf.bvalues,SIG_MF_allcmpts,Sig_free,ADC_MF_allcmpts_S0,ADC_MF_allcmpts,'MF signal');
            PLOT_SIGNAL(experi_mf.bvalues,SIG_MFGA_allcmpts,Sig_free,ADC_MFGA_allcmpts_S0,ADC_MFGA_allcmpts,'MFGA signal');
            PLOT_SIGNAL_BTPDE_MF(experi_btpde,SIG_BTPDE_allcmpts,SIG_MF_allcmpts,SIG_MFGA_allcmpts);
        end
    end
end