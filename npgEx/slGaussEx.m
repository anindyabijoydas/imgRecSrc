function slGaussEx(op)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%     Reconstruction of Nonnegative Sparse Signals Using Accelerated
%                      Proximal-Gradient Algorithms
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   Author: Renliang Gu (renliang@iastate.edu)
%
%          Skyline Gaussian Linear example, no background noise
%           Vary the number of measurements, with continuation


if(~exist('op','var')) op='run'; end

switch lower(op)
    case 'run'
        filename = [mfilename '.mat'];
        if(~exist(filename,'file')) save(filename,'filename'); else load(filename); end
        clear('opt'); filename = [mfilename '.mat'];

        RandStream.setGlobalStream(RandStream.create('mt19937ar','seed',0));
        opt.maxItr=1e4; opt.thresh=1e-6; opt.debugLevel=1;
        m = [ 200, 250, 300, 350, 400, 500, 600, 700, 800]; % should go from 200
        u = [1e-3,1e-3,1e-4,1e-4,1e-5,1e-5,1e-6,1e-6,1e-6];
        Opt=opt;
        for k=1:5
            for i=length(m)
                opt=Opt; opt.m=m(i); opt.snr=inf;
                [y,Phi,Phit,Psi,Psit,opt,~,invEAAt]=loadLinear(opt);
                initSig = Phit(invEAAt*y);

                opt.u = u(i)*10.^(-2:2);
                %gnet{i,k}=Wrapper.glmnet(Phi,wvltMat(length(opt.trueAlpha),dwt_L,daub),y,initSig,opt);

                for j=3
                    fprintf('%s, i=%d, j=%d, k=%d\n','NPG',i,j,k);
                    opt.u = u(i)*10^(j-3)*pNorm(Psit(Phit(y)),inf);


                    npg      {i,j,k}=Wrapper.NPG     (Phi,Phit,Psi,Psit,y,initSig,opt);
                    keyboard
                    return;
                    at       {i,j,k}=Wrapper.AT      (Phi,Phit,Psi,Psit,y,initSig,opt);
                    condat   {i,j,k}=Wrapper.Condat  (Phi,Phit,Psi,Psit,y,initSig,opt);
                    gfb      {i,j,k}=Wrapper.GFB     (Phi,Phit,Psi,Psit,y,initSig,opt);
                    npgc     {i,j,k}=Wrapper.NPGc    (Phi,Phit,Psi,Psit,y,initSig,opt);
                    keyboard
                    continue;

                    ga_gfb = 1.8;
                    la_gfb = 1;
                    nIter = 100; % number of iterations per experiments
                    nIterInf = 1000; % number of iterations to reach minimum energy
                    tic
                    F = @(aaa) Utils.linearModel(aaa,Phi,Phit,y);
                    G = @(x) opt.u*pNorm(Psit(x),1);
                    gradF = @(x) Utils.getNthOutPut(F,x,2);
                    proxGi{1} = @(x,ga) Psi(Utils.softThresh( Psit(x), ga*opt.u));
                    proxGi{2} = @(x,ga) max(x,0);
                    report = @(x)F(x)+G(x);
                    [xGFB, eGFB] = GeneralizedForwardBackward( gradF, proxGi, zeros( [length(initSig) 2] ), opt.maxItr, ga_gfb, la_gfb, true, report );
                    keyboard

                    temp=opt; opt.thresh=1e-12; opt.maxItr=5e4;
                    % pgc12{i,j,k}=Wrapper.PGc(Phi,Phit,Psi,Psit,y,initSig,opt);
                    %sparsn12{i,j,k}=Wrapper.SpaRSAp(Phi,Phit,Psi,Psit,y,initSig,opt);
                    %spiral12{i,j,k}=Wrapper.SPIRAL (Phi,Phit,Psi,Psit,y,initSig,opt);
                    sparsa12 {i,j,k}=Wrapper.SpaRSA   (Phi,Phit,Psi,Psit,y,initSig,opt);
                    opt=temp;

                    npgsc    {i,j,k}=Wrapper.NPGsc    (Phi,Phit,Psi,Psit,y,initSig,opt);
                    npgs     {i,j,k}=Wrapper.NPGs     (Phi,Phit,Psi,Psit,y,initSig,opt);

                    continue;

                    npgsT {i,j,k}=Wrapper.NPGs   (Phi,Phit,Psi,Psit,y,initSig,opt);
                    temp=opt; opt.initStep='fixed';
                    fistal{i,j,k}=Wrapper.FISTA(Phi,Phit,Psi,Psit,y,initSig,opt);
                    opt=temp;
                    continue;

                    fpc      {i,j,k}=Wrapper.FPC      (Phi,Phit,Psi,Psit,y,initSig,opt);
                    sparsa   {i,j,k}=Wrapper.SpaRSA   (Phi,Phit,Psi,Psit,y,initSig,opt);
                    npgc_nads{i,j,k}=Wrapper.NPGc_nads(Phi,Phit,Psi,Psit,y,initSig,opt);
                    npg_nads {i,j,k}=Wrapper.NPG_nads (Phi,Phit,Psi,Psit,y,initSig,opt);
                    pgc      {i,j,k}=Wrapper.PGc      (Phi,Phit,Psi,Psit,y,initSig,opt);
                    sparsn   {i,j,k}=Wrapper.SpaRSAp  (Phi,Phit,Psi,Psit,y,initSig,opt);
                    spiral   {i,j,k}=Wrapper.SPIRAL   (Phi,Phit,Psi,Psit,y,initSig,opt);
                    fista    {i,j,k}=Wrapper.FISTA    (Phi,Phit,Psi,Psit,y,initSig,opt);
                    fpcas    {i,j,k}=Wrapper.FPCas    (Phi,Phit,Psi,Psit,y,initSig,opt);
                end

                save(filename);
            end
        end

    case 'plot'

        load([mfilename '.mat']);

        m = [ 200, 250, 300, 350, 400, 500, 600, 700, 800]; % should go from 200
        u = [1e-3,1e-3,1e-4,1e-4,1e-5,1e-5,1e-6,1e-6,1e-6];
        idx=2:2:7;
        K = 1;

        npgTime   = mean(Cell.getField(   npg(:,:,1:K),'time'),3);
        npgcTime  = mean(Cell.getField(  npgc(:,:,1:K),'time'),3);
        npgsTime  = mean(Cell.getField(  npgs(:,:,1:K),'time'),3);
        npgscTime = mean(Cell.getField( npgsc(:,:,1:K),'time'),3);
        spiralTime= mean(Cell.getField(spiral(:,:,1:K),'time'),3);
        fpcasTime = mean(Cell.getField( fpcas(:,:,1:K),'cpu' ),3);
        fpcTime   = mean(Cell.getField(   fpc(:,:,1:K),'time' ),3);
        fistaTime = mean(Cell.getField( fista(:,:,1:K),'time'),3);
        sparsaTime= mean(Cell.getField(sparsa(:,:,1:K),'time'),3);
        sparsnTime= mean(Cell.getField(sparsn(:,:,1:K),'time'),3);

        npgCost   = mean(Cell.getField(   npg(:,:,1:K),'cost'),3);
        npgcCost  = mean(Cell.getField(  npgc(:,:,1:K),'cost'),3);
        npgsCost  = mean(Cell.getField(  npgs(:,:,1:K),'cost'),3);
        npgscCost = mean(Cell.getField( npgsc(:,:,1:K),'cost'),3);
        spiralCost= mean(Cell.getField(spiral(:,:,1:K),'cost'),3);
        fpcasCost = mean(Cell.getField( fpcas(:,:,1:K),'f'   ),3);
        fpcCost   = mean(Cell.getField(   fpc(:,:,1:K),'cost' ),3);
        fistaCost = mean(Cell.getField( fista(:,:,1:K),'cost'),3);
        sparsaCost= mean(Cell.getField(sparsa(:,:,1:K),'cost'),3);
        sparsnCost= mean(Cell.getField(sparsn(:,:,1:K),'cost'),3);

        npgRMSE   = mean(Cell.getField(   npg(:,:,1:K),'RMSE'),3);
        npgcRMSE  = mean(Cell.getField(  npgc(:,:,1:K),'RMSE'),3);
        npgsRMSE  = mean(Cell.getField(  npgs(:,:,1:K),'RMSE'),3);
        npgscRMSE = mean(Cell.getField( npgsc(:,:,1:K),'RMSE'),3);
        spiralRMSE= mean(Cell.getField(spiral(:,:,1:K),'reconerror'),3);
        fpcasRMSE = mean(Cell.getField( fpcas(:,:,1:K),'RMSE'),3);
        fpcRMSE   = mean(Cell.getField(   fpc(:,:,1:K),'RMSE' ),3);
        fistaRMSE = mean(Cell.getField( fista(:,:,1:K),'RMSE'),3);
        sparsaRMSE= mean(Cell.getField(sparsa(:,:,1:K),'RMSE'),3);
        sparsnRMSE= mean(Cell.getField(sparsn(:,:,1:K),'RMSE'),3);

        npgnasTime = mean(Cell.getField(   npg_nads(:,:,1:K),'time'),3);
        npgcnasTime= mean(Cell.getField(  npgc_nads(:,:,1:K),'time'),3);
        npgnasCost = mean(Cell.getField(   npg_nads(:,:,1:K),'cost'),3);
        npgcnasCost= mean(Cell.getField(  npgc_nads(:,:,1:K),'cost'),3);
        npgnasRMSE = mean(Cell.getField(   npg_nads(:,:,1:K),'RMSE'),3);
        npgcnasRMSE= mean(Cell.getField(  npgc_nads(:,:,1:K),'RMSE'),3);

        for i=1:length(m)
            temp=[];
            for k=1:K
                temp(:,k)=gnet{i,k}.RMSE(:);
            end
            %       gnetRMSE(i,:)=mean(temp,2)';
        end

        [r,c1]=find(   npgRMSE== repmat(min(   npgRMSE,[],2),1,5)); [r,idx1]=sort(r);
        [r,c2]=find(  npgcRMSE== repmat(min(  npgcRMSE,[],2),1,5)); [r,idx2]=sort(r);
        [r,c4]=find(spiralRMSE== repmat(min(spiralRMSE,[],2),1,5)); [r,idx4]=sort(r);
        [r,c8]=find(sparsnRMSE== repmat(min(sparsnRMSE,[],2),1,5)); [r,idx8]=sort(r);

        [r,c3]=find(  npgsRMSE== repmat(min(  npgsRMSE,[],2),1,5)); [r,idx3]=sort(r);
        [r,c5]=find( fpcasRMSE== repmat(min( fpcasRMSE,[],2),1,5)); [r,idx5]=sort(r);
        [r,c6]=find( fistaRMSE== repmat(min( fistaRMSE,[],2),1,5)); [r,idx6]=sort(r);
        [r,c7]=find(sparsaRMSE== repmat(min(sparsaRMSE,[],2),1,5)); [r,idx7]=sort(r);
        [r,c9]=find( npgscRMSE== repmat(min( npgscRMSE,[],2),1,5)); [r,idx9]=sort(r);
        disp([c1(idx1), c2(idx2), c4(idx4), c8(idx8) zeros(9,1) c3(idx3), c5(idx5), c6(idx6), c7(idx7), c9(idx9) ]);
        keyboard
        uNonneg=[3 3 3 3 4 4 4 4 3];
        uNeg=[4 4 4 4 4 4 4 4 3];
        figure;
        semilogy(m,   npgRMSE((c1(idx1)-1)*9+(1:9)'),'r-*'); hold on;
        semilogy(m,  npgcRMSE((c2(idx2)-1)*9+(1:9)'),'c-p');
        semilogy(m,  npgsRMSE((c3(idx3)-1)*9+(1:9)'),'k-s');
        semilogy(m,spiralRMSE((c4(idx4)-1)*9+(1:9)'),'k-^');
        semilogy(m, fpcasRMSE((c5(idx5)-1)*9+(1:9)'),'g-o');
        semilogy(m, fistaRMSE((c6(idx6)-1)*9+(1:9)'),'b-.');
        semilogy(m,sparsaRMSE((c7(idx7)-1)*9+(1:9)'),'y-p');
        semilogy(m,sparsnRMSE((c8(idx8)-1)*9+(1:9)'),'r-x');
        semilogy(m, npgscRMSE((c9(idx9)-1)*9+(1:9)'),'k-.');
        legend('npg','npgc','npgs','spiral','fpcas','fista','sparsa','sparsa','npgsc');
        figure;
        semilogy(m,   npgTime((c1(idx1)-1)*9+(1:9)'),'r-*'); hold on;
        semilogy(m,  npgcTime((c2(idx2)-1)*9+(1:9)'),'c-p');
        semilogy(m,  npgsTime((c3(idx3)-1)*9+(1:9)'),'k-s');
        semilogy(m,spiralTime((c4(idx4)-1)*9+(1:9)'),'k-^');
        semilogy(m, fpcasTime((c5(idx5)-1)*9+(1:9)'),'g-o');
        semilogy(m, fistaTime((c6(idx6)-1)*9+(1:9)'),'b-.');
        semilogy(m,sparsaTime((c7(idx7)-1)*9+(1:9)'),'y-p');
        semilogy(m,sparsnTime((c8(idx8)-1)*9+(1:9)'),'r-x');
        semilogy(m, npgscTime((c9(idx9)-1)*9+(1:9)'),'k-.');
        legend('npg','npgc','npgs','spiral','fpcas','fista','sparsa','sparsa','npgsc');
        figure;
        semilogy(m,   npgRMSE((uNonneg-1)*9+(1:9)),'r-*'); hold on;
        semilogy(m,  npgcRMSE((uNonneg-1)*9+(1:9)),'c-p');
        semilogy(m,spiralRMSE((uNonneg-1)*9+(1:9)),'k-^');
        semilogy(m,sparsnRMSE((uNonneg-1)*9+(1:9)),'r-x');
        semilogy(m,  npgsRMSE((uNonneg-1)*9+(1:9)),'k-s');
        semilogy(m, fpcasRMSE((uNonneg-1)*9+(1:9)),'g-o');
        semilogy(m, fistaRMSE((uNonneg-1)*9+(1:9)),'b-.');
        semilogy(m,sparsaRMSE((uNonneg-1)*9+(1:9)),'y-p');
        %   semilogy(m,  gnetRMSE((uNonneg-1)*9+(1:9)),'r:>');
        semilogy(m, npgscRMSE((uNonneg-1)*9+(1:9)),'k-.');
        legend('npg','npgc','spiral','sparsa','npgs','fpcas','fista','sparsa','npgsc');
        figure;
        semilogy(m,   npgTime((uNonneg-1)*9+(1:9)),'r-*'); hold on;
        semilogy(m,  npgcTime((uNonneg-1)*9+(1:9)),'c-p');
        semilogy(m,spiralTime((uNonneg-1)*9+(1:9)),'k-^');
        semilogy(m,sparsnTime((uNonneg-1)*9+(1:9)),'r-x');
        semilogy(m,  npgsTime((uNonneg-1)*9+(1:9)),'k-s');
        semilogy(m, fpcasTime((uNonneg-1)*9+(1:9)),'g-o');
        semilogy(m, fistaTime((uNonneg-1)*9+(1:9)),'b-.');
        semilogy(m,sparsaTime((uNonneg-1)*9+(1:9)),'y-p');
        semilogy(m, npgscTime((uNonneg-1)*9+(1:9)),'k-.');
        legend('npg','npgc','spiral','sparsa','npgs','fpcas','fista','sparsa','npgsc');

        f=fopen('selectedTime.data','w');
        for mIdx=1:length(m)
            fprintf(f,'%e\t%e\t%e\t%e\t%e\t%e\t%e\t%e\t%e\t%d\t%s\t%s\n',...
                npgTime(mIdx,uNonneg(mIdx)), ...
                npgcTime(mIdx,uNonneg(mIdx)), ...
                spiralTime(mIdx,uNonneg(mIdx)), ...
                sparsnTime(mIdx,uNonneg(mIdx)), ...
                npgsTime(mIdx,uNonneg(mIdx)), ...
                npgscTime(mIdx,uNonneg(mIdx)), ...
                fpcasTime(mIdx,uNonneg(mIdx)), ...
                fistaTime(mIdx,uNonneg(mIdx)), ...
                sparsaTime(mIdx,uNonneg(mIdx)), ...
                m(mIdx),num2str(log10(u((mIdx)))+uNonneg(mIdx)-3), num2str(log10(u(mIdx))+uNeg(mIdx)-3));
        end
        fclose(f);

        keyboard

        as=1:5;
        forSave=[]; forTime=[];
        for mIdx=idx
            figure(900);
            semilogy(log10(u(mIdx))+as-3,    npgRMSE(mIdx,as),'r-*'); hold on;
            semilogy(log10(u(mIdx))+as-3,   npgcRMSE(mIdx,as),'r.-');
            semilogy(log10(u(mIdx))+as-3, sparsnRMSE(mIdx,as),'r-s');
            semilogy(log10(u(mIdx))+as-3, spiralRMSE(mIdx,as),'r-^');
            semilogy(log10(u(mIdx))+as-3,   npgsRMSE(mIdx,as),'k-s');
            semilogy(log10(u(mIdx))+as-3,  fpcasRMSE(mIdx,as),'g-o');
            semilogy(log10(u(mIdx))+as-3,  fistaRMSE(mIdx,as),'g-.');
            semilogy(log10(u(mIdx))+as-3, sparsaRMSE(mIdx,as),'g->');
            semilogy(log10(u(mIdx))+as-3,  npgscRMSE(mIdx,as),'g-*');
            semilogy(log10(u(mIdx))+as-3,    fpcRMSE(mIdx,as),'g:p');
            semilogy(gnet{mIdx,1}.a,   gnet{mIdx,1}.RMSE(:),'r:>');

            forSave=[forSave log10(u(mIdx))+as(:)-3];
            forSave=[forSave reshape(   npgRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape(  npgcRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape(sparsnRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape(spiralRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape(  npgsRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape( fpcasRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape( fistaRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape(sparsaRMSE(mIdx,as),[],1)];
            forSave=[forSave reshape( npgscRMSE(mIdx,as),[],1)];

            figure;
            semilogy(log10(u(mIdx))+as-3,    npgTime(mIdx,as),'r-*'); hold on;
            semilogy(log10(u(mIdx))+as-3,   npgcTime(mIdx,as),'r.-');
            semilogy(log10(u(mIdx))+as-3, sparsnTime(mIdx,as),'r-s');
            semilogy(log10(u(mIdx))+as-3, spiralTime(mIdx,as),'r-^');
            semilogy(log10(u(mIdx))+as-3,   npgsTime(mIdx,as),'k-s');
            semilogy(log10(u(mIdx))+as-3,  fpcasTime(mIdx,as),'g-o');
            semilogy(log10(u(mIdx))+as-3,  fistaTime(mIdx,as),'g-.');
            semilogy(log10(u(mIdx))+as-3, sparsaTime(mIdx,as),'g->');
            semilogy(log10(u(mIdx))+as-3,  npgscTime(mIdx,as),'g-*');
            semilogy(log10(u(mIdx))+as-3,    fpcTime(mIdx,as),'g:p');
            legend('npg','npgc','sparsn','spiral','npgs','fpcas','fista','sparsa','npgsc','fpc');
            title(sprintf('mIdx=%d',mIdx));

            forTime=[forTime log10(u(mIdx))+as(:)-3];
            forTime=[forTime reshape(   npgTime(mIdx,as),[],1)];
            forTime=[forTime reshape(  npgcTime(mIdx,as),[],1)];
            forTime=[forTime reshape(sparsnTime(mIdx,as),[],1)];
            forTime=[forTime reshape(spiralTime(mIdx,as),[],1)];
            forTime=[forTime reshape(  npgsTime(mIdx,as),[],1)];
            forTime=[forTime reshape( fpcasTime(mIdx,as),[],1)];
            forTime=[forTime reshape( fistaTime(mIdx,as),[],1)];
            forTime=[forTime reshape(sparsaTime(mIdx,as),[],1)];
            forTime=[forTime reshape( npgscTime(mIdx,as),[],1)];
        end
        figure(900); 
        legend('npg','npgc','sparsn','spiral','npgs','fpcas','fista','sparsa','npgsc','fpc','glmnet');
        save('rmseVsA.data','forSave','-ascii');
        save('timeVsA.data','forTime','-ascii');

        keyboard

        mIdx=6; as=gEle(c2(idx2),mIdx); forSave=[]; t=0;
        q=(1:max(find(sparsn12{mIdx,as}.cost(:)>=sparsn{mIdx,as}.cost(end))))';
        t=t+1; temp=      npg{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=      npg{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=      npg{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp; % 3rd col
        t=t+1; temp=      npg{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgc{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgc{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgc{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp; % 7th col
        t=t+1; temp=     npgc{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.RMSE(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.time(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.cost(q);     forSave(1:length(temp),t)=temp; % 11th col
        t=t+1; temp= sparsn12{mIdx,as}.difAlpha(q); forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsn12{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        q=(1:max(find(spiral12{mIdx,as}.cost(:)>=spiral{mIdx,as}.cost(end))))';
        t=t+1; temp= spiral12{mIdx,as}.RMSE(q);     forSave(1:length(temp),t)=temp; % 17th col
        t=t+1; temp= spiral12{mIdx,as}.time(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= spiral12{mIdx,as}.cost(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= spiral12{mIdx,as}.difAlpha(q); forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgs{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgs{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgs{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=     npgs{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=    npgsc{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=    npgsc{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=    npgsc{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=    npgsc{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        q=(1:max(find(sparsa12{mIdx,as}.cost(:)>=sparsa{mIdx,as}.cost(end))))';
        t=t+1; temp= sparsa12{mIdx,as}.RMSE(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.time(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.cost(q);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.difAlpha(q); forSave(1:length(temp),t)=temp;
        t=t+1; temp=      fpc{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=      fpc{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=      fpc{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=      fpc{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= sparsa12{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=    fista{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp; % 41st col
        t=t+1; temp=    fista{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=    fista{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=    fista{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp= spiral12{mIdx,as}.RMSE(:);     forSave(1:length(temp),t)=temp; % 45th col
        t=t+1; temp= spiral12{mIdx,as}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= spiral12{mIdx,as}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= spiral12{mIdx,as}.difAlpha(:); forSave(1:length(temp),t)=temp;
        save('traceLinGauss.data','forSave','-ascii');

        mc=forSave(:,[3,7,11,19]); mc = min(mc(mc(:)>0));
        figure;
        loglog(forSave(:, 2),forSave(:, 3)-mc,'r-'); hold on;
        loglog(forSave(:, 6),forSave(:, 7)-mc,'r-.');
        loglog(forSave(:,14),forSave(:,15)-mc,'c--');
        loglog(forSave(:,18),forSave(:,19)-mc,'b:'); 
        legend('npg','npgc','sprsa 12','spiral');

        mc=forSave(:,[23,27,31,35,39,43]); mc = min(mc(mc(:)>0));
        figure;
        loglog(forSave(:,22),forSave(:,23)-mc,'r-'); hold on;
        loglog(forSave(:,26),forSave(:,27)-mc,'g-.');
        loglog(forSave(:,30),forSave(:,31)-mc,'c--');
        loglog(forSave(:,34),forSave(:,35)-mc,'b:'); 
        loglog(forSave(:,38),forSave(:,39)-mc,'k-'); 
        loglog(forSave(:,42),forSave(:,43)-mc,'r--'); 
        legend('npgs','npgsc','sparsa','fpc','sparsa12','fista');

        keyboard

        mIdx=6; as=gEle(c2(idx2),mIdx); forSave=[]; t=0;
        t=t+1; temp=  npgc{mIdx,as}.RMSE(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp=  npgc{mIdx,as}.time(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp=  npgc{mIdx,as}.cost(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp=  npgc{mIdx,as}.difAlpha(:);  forSave(1:length(temp),t)=temp;
        t=t+1; temp=  npgc{mIdx,as}.uRecord(:,2); forSave(1:length(temp),t)=temp;
        t=t+1; temp=  npgc{mIdx,as}.contThresh(:);forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.RMSE(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.time(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.cost(:);      forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.difAlpha(:);  forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.uRecord(:,2); forSave(1:length(temp),t)=temp;
        t=t+1; temp= npgsc{mIdx,as}.contThresh(:);forSave(1:length(temp),t)=temp;
        save('continuation.data','forSave','-ascii');

        keyboard

        temp = 4;
        signal=npg{1}.opt.trueAlpha;
        signal=[signal,    npg{gEle((c1(idx1)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal,   npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal,   npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal, spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal,  fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal,  fista{gEle((c6(idx6)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal, sparsa{gEle((c7(idx7)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal, sparsn{gEle((c8(idx8)-1)*9+(1:9)',temp)}.alpha];
        signal=[signal,  npgsc{gEle((c9(idx9)-1)*9+(1:9)',temp)}.alpha];
        save('skyline.data','signal','-ascii');

        [gEle((c1(idx1)-1),temp);
        gEle((c2(idx2)-1),temp);
        gEle((c3(idx3)-1),temp);
        gEle((c4(idx4)-1),temp);
        gEle((c5(idx5)-1),temp);
        gEle((c6(idx6)-1),temp);
        gEle((c7(idx7)-1),temp);
        gEle((c8(idx8)-1),temp);
        gEle((c9(idx9)-1),temp);]'

        figure; plot(signal(:,2)); hold on; plot(signal(:,1),'r'); title('NPG');
        figure; plot(signal(:,4)); hold on; plot(signal(:,1),'r'); title('NPGs');
        figure; plot(signal(:,6)); hold on; plot(signal(:,1),'r'); title('FPCas');
        fprintf('\nfor N=350:\n'); temp=4;
        fprintf('   npgRec RMSE: %g%% -> %g%%\n',   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgcRec RMSE: %g%% -> %g%%\n',  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgsRec RMSE: %g%% -> %g%%\n',  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)})*100);
        fprintf('spiralRec RMSE: %g%% -> %g%%\n',spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)}.reconerror(end)*100,rmseTruncate(spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)})*100);
        fprintf(' fpcasRec RMSE: %g%% -> %g%%\n', fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)})*100);
        fprintf(' fistaRec RMSE: %g%% -> %g%%\n', fista{gEle((c6(idx6)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fista{gEle((c6(idx6)-1)*9+(1:9)',temp)})*100);

        fprintf('\nfor N=250:\n'); temp=2;
        fprintf('   npgRec RMSE: %g%% -> %g%%\n',   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgcRec RMSE: %g%% -> %g%%\n',  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgsRec RMSE: %g%% -> %g%%\n',  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)})*100);
        fprintf('spiralRec RMSE: %g%% -> %g%%\n',spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)}.reconerror(end)*100,rmseTruncate(spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)})*100);
        fprintf(' fpcasRec RMSE: %g%% -> %g%%\n', fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)})*100);
        fprintf(' fistaRec RMSE: %g%% -> %g%%\n', fista{gEle((c6(idx6)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fista{gEle((c6(idx6)-1)*9+(1:9)',temp)})*100);

        fprintf('\nfor N=500:\n'); temp=6;
        fprintf('   npgRec RMSE: %g%% -> %g%%\n',   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(   npg{gEle((c1(idx1)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgcRec RMSE: %g%% -> %g%%\n',  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgc{gEle((c2(idx2)-1)*9+(1:9)',temp)})*100);
        fprintf('  npgsRec RMSE: %g%% -> %g%%\n',  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate(  npgs{gEle((c3(idx3)-1)*9+(1:9)',temp)})*100);
        fprintf('spiralRec RMSE: %g%% -> %g%%\n',spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)}.reconerror(end)*100,rmseTruncate(spiral{gEle((c4(idx4)-1)*9+(1:9)',temp)})*100);
        fprintf(' fpcasRec RMSE: %g%% -> %g%%\n', fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fpcas{gEle((c5(idx5)-1)*9+(1:9)',temp)})*100);
        fprintf(' fistaRec RMSE: %g%% -> %g%%\n', fista{gEle((c6(idx6)-1)*9+(1:9)',temp)}.RMSE(end)*100      ,rmseTruncate( fista{gEle((c6(idx6)-1)*9+(1:9)',temp)})*100);

        M=length(m);
        str=        '$m$            ';              for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%10d',str,m(i)); end; end;
        str=sprintf('%s\\\\\\hline',str);
        str=sprintf('%s\\\\\nNPG            ', str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str,   npg{gEle((c1(idx1)-1)*9+(1:9)',i)}.cost(end));end; end;
        str=sprintf('%s\\\\\nNPG$_\\text{C}$ ',str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str,  npgc{gEle((c2(idx2)-1)*9+(1:9)',i)}.cost(end));end; end;
        str=sprintf('%s\\\\\nNPG$_\\text{S}$ ',str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str,  npgs{gEle((c3(idx3)-1)*9+(1:9)',i)}.cost(end));end; end;
        str=sprintf('%s\\\\\nSPIRAL         ', str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str,spiral{gEle((c4(idx4)-1)*9+(1:9)',i)}.cost(end));end; end;
        str=sprintf('%s\\\\\nFPC$_\\text{AS}$',str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str, fpcas{gEle((c5(idx5)-1)*9+(1:9)',i)}.f   (end));end; end;
        str=sprintf('%s\nFISTA          ', str);    for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str, fista{gEle((c6(idx6)-1)*9+(1:9)',i)}.cost(end));end; end;
        str=sprintf('%s\\\\\nSpaRSA         ', str);for i=1:M;if(mod(m(i),100)==0);str=sprintf('%s&%-10.4g',str,spiral{gEle((c7(idx7)-1)*9+(1:9)',i)}.cost(end));end; end;
        file=fopen('varyMeasurementTable.tex','w'); fprintf(file,'%s',str); fclose(file);

        % figure;
        % for i=1:M;
        %     semilogy(npgs{i,idx3,1}.stepSize); hold on; semilogy(fista{i,idx6,1}.stepSize,'r:');
        %     semilogy([1,length(fista{i,idx6,1}.RMSE)],ones(1,2)*1/fista{i,idx6,1}.opt.L,'k-.');
        %     hold off;
        %     pause;
        % end
        npgItr=[];   
        npgcItr=[];
        npgsItr=[];
        spiralItr=[];
        fpcasItr=[];
        fistaItr=[];
        sparsaItr=[];
        sparsnItr=[];
        npgscItr=[];

        for i=1:K
            temp=   npg(:,:,i); temp=temp((c1(idx1)-1)*9+(1:9)');    npgItr=[   npgItr,showResult(temp,2,'p'   )];
            temp=  npgc(:,:,i); temp=temp((c2(idx2)-1)*9+(1:9)');   npgcItr=[  npgcItr,showResult(temp,2,'p'   )];
            temp=  npgs(:,:,i); temp=temp((c3(idx3)-1)*9+(1:9)');   npgsItr=[  npgsItr,showResult(temp,2,'p'   )];
            temp=spiral(:,:,i); temp=temp((c4(idx4)-1)*9+(1:9)'); spiralItr=[spiralItr,showResult(temp,2,'p'   )];
            temp= fpcas(:,:,i); temp=temp((c5(idx5)-1)*9+(1:9)');  fpcasItr=[ fpcasItr,showResult(temp,2,'itr' )];
            temp= fista(:,:,i); temp=temp((c6(idx6)-1)*9+(1:9)');  fistaItr=[ fistaItr,showResult(temp,2,'p'   )];
            temp=sparsa(:,:,i); temp=temp((c7(idx7)-1)*9+(1:9)'); sparsaItr=[sparsaItr,showResult(temp,3,'RMSE')];
            temp=sparsn(:,:,i); temp=temp((c8(idx8)-1)*9+(1:9)'); sparsnItr=[sparsnItr,showResult(temp,3,'RMSE')];
            temp= npgsc(:,:,i); temp=temp((c9(idx9)-1)*9+(1:9)');  npgscItr=[ npgscItr,showResult(temp,2,'p'   )];
        end

        forSave=[];
        forSave=[forSave,    npgTime((c1(idx1)-1)*9+(1:9)')];
        forSave=[forSave,   npgcTime((c2(idx2)-1)*9+(1:9)')];
        forSave=[forSave,   npgsTime((c3(idx3)-1)*9+(1:9)')];
        forSave=[forSave, spiralTime((c4(idx4)-1)*9+(1:9)')];
        forSave=[forSave,  fpcasTime((c5(idx5)-1)*9+(1:9)')];
        forSave=[forSave,  fistaTime((c6(idx6)-1)*9+(1:9)')];

        forSave=[forSave,    npgCost((c1(idx1)-1)*9+(1:9)')];
        forSave=[forSave,   npgcCost((c2(idx2)-1)*9+(1:9)')];
        forSave=[forSave,   npgsCost((c3(idx3)-1)*9+(1:9)')];
        forSave=[forSave, spiralCost((c4(idx4)-1)*9+(1:9)')];
        forSave=[forSave,  fpcasCost((c5(idx5)-1)*9+(1:9)')];
        forSave=[forSave,  fistaCost((c6(idx6)-1)*9+(1:9)')];

        forSave=[forSave,    npgRMSE((c1(idx1)-1)*9+(1:9)')];
        forSave=[forSave,   npgcRMSE((c2(idx2)-1)*9+(1:9)')];
        forSave=[forSave,   npgsRMSE((c3(idx3)-1)*9+(1:9)')];
        forSave=[forSave, spiralRMSE((c4(idx4)-1)*9+(1:9)')];
        forSave=[forSave,  fpcasRMSE((c5(idx5)-1)*9+(1:9)')];
        forSave=[forSave,  fistaRMSE((c6(idx6)-1)*9+(1:9)')];
        forSave=[forSave, m(:)];
        forSave=[forSave, sparsaTime((c7(idx7)-1)*9+(1:9)')];
        forSave=[forSave, sparsaCost((c7(idx7)-1)*9+(1:9)')];
        forSave=[forSave, sparsaRMSE((c7(idx7)-1)*9+(1:9)')];
        forSave=[forSave, sparsnTime((c8(idx8)-1)*9+(1:9)')];
        forSave=[forSave, sparsnCost((c8(idx8)-1)*9+(1:9)')];
        forSave=[forSave, sparsnRMSE((c8(idx8)-1)*9+(1:9)')];
        forSave=[forSave,  npgscTime((c9(idx9)-1)*9+(1:9)')];
        forSave=[forSave,  npgscCost((c9(idx9)-1)*9+(1:9)')];
        forSave=[forSave,  npgscRMSE((c9(idx9)-1)*9+(1:9)')];
        save('varyMeasurement.data','forSave','-ascii');

        forSave=m(:);
        forSave=[forSave,    npgTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave,   npgcTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave, spiralTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave, sparsnTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave,   npgsTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave,  fpcasTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave,  fistaTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave, sparsaTime((uNonneg-1)*9+(1:9))'];
        forSave=[forSave,  npgscTime((uNonneg-1)*9+(1:9))'];
        save('varyMeasurementTime.data','forSave','-ascii');

        keyboard

        mIdx=2; experi=1; forSave=[]; t=0;
        npgsT=npgsT(:,:,experi); npgsn20T=npgs(:,:,experi); fistaT=fista(:,:,experi); fistalT=fistal(:,:,experi); fistalT{9,6}=[];
        t=t+1; temp=   npgsT{mIdx,gEle(c3(idx3),mIdx)}.stepSize(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=npgsn20T{mIdx,gEle(c3(idx3),mIdx)}.stepSize(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=  fistaT{mIdx,gEle(c3(idx3),mIdx)}.stepSize(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp= fistalT{mIdx,gEle(c3(idx3),mIdx)}.stepSize(:); forSave(1:length(temp),t)=temp;
        t=t+1; temp=   npgsT{mIdx,gEle(c3(idx3),mIdx)}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=npgsn20T{mIdx,gEle(c3(idx3),mIdx)}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=  fistaT{mIdx,gEle(c3(idx3),mIdx)}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= fistalT{mIdx,gEle(c3(idx3),mIdx)}.RMSE(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=   npgsT{mIdx,gEle(c3(idx3),mIdx)}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=npgsn20T{mIdx,gEle(c3(idx3),mIdx)}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=  fistaT{mIdx,gEle(c3(idx3),mIdx)}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= fistalT{mIdx,gEle(c3(idx3),mIdx)}.time(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=   npgsT{mIdx,gEle(c3(idx3),mIdx)}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=npgsn20T{mIdx,gEle(c3(idx3),mIdx)}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp=  fistaT{mIdx,gEle(c3(idx3),mIdx)}.cost(:);     forSave(1:length(temp),t)=temp;
        t=t+1; temp= fistalT{mIdx,gEle(c3(idx3),mIdx)}.cost(:);     forSave(1:length(temp),t)=temp;
        disp([ c3(idx3) c6(idx6)]);
        disp([   npgsT{mIdx,gEle(c3(idx3),mIdx)}.p;...
            fistalT{mIdx,gEle(c3(idx3),mIdx)}.p;...
            fistaT{mIdx,gEle(c6(idx6),mIdx)}.p]);
        disp([   npgsT{mIdx,gEle(c3(idx3),mIdx)}.time(end); ...
            fistalT{mIdx,gEle(c3(idx3),mIdx)}.time(end); ...
            fistaT{mIdx,gEle(c6(idx6),mIdx)}.time(end)]);
        temp=forSave(:,13:16); temp=temp(:); temp=temp(temp>0); temp=min(temp); forSave(:,13:16)=forSave(:,13:16)-temp;
        save('stepSizeLin.data','forSave','-ascii');
        figure(1); hold off; semilogy(forSave(:,9),forSave(:,5),'r'); hold on;
        semilogy(forSave(:,10),forSave(:,6),'g');
        semilogy(forSave(:,11),forSave(:,7),'b');
        semilogy(forSave(:,12),forSave(:,8),'c');
        legend('npgs','npgs20','fistaBB','fistaL');
        figure(2); hold off; semilogy(forSave(:,9),forSave(:,13),'r'); hold on;
        semilogy(forSave(:,10),forSave(:,14),'g');
        semilogy(forSave(:,11),forSave(:,15),'b');
        semilogy(forSave(:,12),forSave(:,16),'c');
        legend('npgs','npgs20','fistaBB','fistaL');
        keyboard

        system(['mv continuation.data traceLinGauss.data selectedTime.data timeVsA.data rmseVsA.data stepSizeLin.data varyMeasurement.data varyMeasurementTime.data skyline.data varyMeasurementTable.tex ' paperDir]);
        disp('done');
end
end
