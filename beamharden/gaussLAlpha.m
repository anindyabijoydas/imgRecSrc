function [f,g,h] = gaussLAlpha(Imea,Ie,alpha,kappa,Phi,Phit,polyIout)
    for i=1:size(alpha,2) R(:,i)=Phi(alpha(:,i)); end
    if(nargout>=3)
        [BLI,sBLI,ssBLI] = polyIout(R,Ie); %A=exp(-R*mu');
    elseif(nargout>=2)
        [BLI,sBLI] = polyIout(R,Ie); %A=exp(-R*mu');
    else
        BLI = polyIout(R,Ie); %A=exp(-R*mu');
    end
    Err=log(BLI./Imea);
    f=Err'*Err/2;
    %zmf=[min(Err(:)); max(Err(:))]; % lb and ub of z-f(theta)
    if(nargout>=2)
        g=-Phit(Err.*sBLI./BLI);
        if(nargout>=3)
            h=@(x,opt) hessian(Phi, Phit,...
                (1-Err).*((sBLI./BLI).^2)+Err.*ssBLI./BLI,...
                x,opt);
        end
    end
end

function h = hessian(Phi, Phit, weight, x, opt)
    y = Phi(x); h = weight.*y;
    if(opt==1)
        h = Phit(h);
    else
        h= y'*y;
    end
end
