function [y,Phi,Phit,Psi,Psit,opt,FBP,mask]=loadYang(opt,seed)
%   n=512;
%   trueImg=zeros(n,n);
%   inFig=rgb2gray(double(imread('yinyang.png')));
%   [~,~,alpha]=imread('yinyang.png');
%   inFig(alpha==0)=0;
%   t1=floor((n-size(inFig,1))/2);
%   t2=ceil((n-size(inFig,1))/2);
%   trueImg(t1+1:n-t2,t1+1:n-t2)=inFig;

    if(~exist('seed','var')) seed=0; end
    RandStream.setGlobalStream(RandStream.create('mt19937ar','seed',seed));
    if(~isfield(opt,'beamharden')) opt.beamharden=false; end

    trueImg=load('yang.mat'); opt.trueImg=trueImg.trueImg;
    conf=ConfigCT();

    daub = 2; dwt_L=6;        %levels of wavelet transform
    maskType='CircleMask';

    conf.PhiMode = 'gpuPrj'; %'parPrj'; %'basic'; %'gpuPrj'; %
    conf.dist = 2000;
    conf.imgSize = size(opt.trueImg,1);
    conf.prjWidth = conf.imgSize;
    conf.prjFull = opt.prjFull;
    conf.prjNum = opt.prjNum;
    conf.dSize = 1;
    conf.effectiveRate = 1;
    conf.Ts = 1;

    detectorBitWidth=16;

    [ops.Phi,ops.Phit,ops.FBP]=conf.genOperators();  % without using mask
    if(opt.beamharden)
        symbol={'Fe'};
        densityMap{1}=opt.trueImg;

        [y,args] = genBeamHarden(symbol,densityMap,ops,...
            'showImg',false);
        opt.iota = args.iota(:);
        opt.epsilon = args.epsilon(:);
        opt.kappa = args.kappa(:);

        opt.trueImg=opt.trueImg*args.density;
        conf.Ts = args.Ts;

        y=-log(y(:)/max(y(:)));

        if strcmpi(opt.noiseType,'poisson')
            %  Poisson measurements
            Imea = 2^detectorBitWidth * exp(-y);
            Imea = poissrnd(Imea);
            y=-log(Imea/max(Imea));
        end
    else
        y = ops.Phi(opt.trueImg);

        % use Gaussian noise
        v = randn(size(y));
        v = v*(norm(y)/sqrt(opt.snr*length(y)));
        y = y + v;
    end

    if(strcmp(maskType,'CircleMask'))
        % reconstruction mask (which pixels do we estimate?)
        mask = Utils.getCircularMask(conf.imgSize);
        wvltName = sprintf('MaskWvlt%dCircleL%dD%d.mat',conf.imgSize,dwt_L,daub);
        if(exist(wvltName,'file'))
            load(wvltName);
        else
            maskk=wvltMask(mask,dwt_L,daub,wvltName);
        end
    end
    opt.mask = mask;
    opt.trueAlpha=opt.trueImg(mask~=0);

    [Phi,Phit,FBP]=conf.genOperators(mask);
    [Psi,Psit]=Utils.getPsiPsit(daub,dwt_L,mask,maskk);

    fprintf('Configuration Finished!\n');
end

