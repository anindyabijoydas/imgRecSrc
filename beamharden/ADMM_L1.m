classdef ADMM_L1 < Methods
    properties
        stepShrnk = 0.5;
        maxItr=1e2;
        preAlpha=0;
        preG=[];
        preY=[];
        s
        Psi_s
        pa
        rho = 1;
        y1=0;
        main
    end
    methods
        function obj = ADMM_L1(n,alpha,maxAlphaSteps,stepShrnk,Psi,Psit)
            obj = obj@Methods(n,alpha);
            obj.coef(1) = 1;
            obj.maxStepNum = maxAlphaSteps;
            obj.stepShrnk = stepShrnk;
            obj.Psi = Psi;
            obj.Psit = Psit;
            obj.s = obj.Psit(alpha);
            obj.Psi_s = obj.Psi(obj.s);
            fprintf('use ADMM_L1 method\n');
            obj.main = @obj.main_0;
        end
        function main_0(obj)
            obj.p = obj.p+1; obj.warned = false;

            subProb = FISTA(obj.n+1,obj.alpha);
            for j=1:obj.n
                subProb.fArray{j} = obj.fArray{j};
            end
            subProb.fArray{obj.n+1} = @(aaa) obj.augLag(aaa,obj.Psi_s-obj.y1);
            subProb.coef = [ones(obj.n,1); obj.rho];
            obj.alpha = subProb.main();

            obj.s = obj.softThresh(...
                obj.Psit(obj.alpha+obj.y1),...
                obj.u/(obj.rho));
            obj.Psi_s = obj.Psi(obj.s);

            obj.y1 = obj.y1 - (obj.Psi_s-obj.alpha);

            obj.func(obj.alpha);
            obj.fVal(obj.n+1) = sum(abs(obj.Psit(obj.alpha)));
            obj.cost = obj.fVal(:)'*obj.coef(:);
        end
        function main_1(obj)
            obj.p = obj.p+1; obj.warned = false;

            %y=obj.alpha+(obj.p-1)/(obj.p+2)*(obj.alpha-obj.preAlpha);
            y=obj.alpha;
            obj.preAlpha = obj.alpha;

            if(isempty(obj.preG))
                [oldCost,grad,hessian] = obj.func(y);
                obj.t = hessian(grad,2)/(grad'*grad);
            else
                [oldCost,grad] = obj.func(y);
                obj.t = abs( (grad-obj.preG)'*(y-obj.preY)/...
                    ((y-obj.preY)'*(y-obj.preY)));
            end
            obj.preY = y; obj.preG = grad;
            extra = obj.rho*(obj.Psi_s-obj.y1-y)-grad;

            % start of line Search
            obj.ppp=0;
            while(1)
                obj.ppp = obj.ppp+1;
                newX = y + (extra)/(obj.t+obj.rho);
                newCost=obj.func(newX);
                if(newCost<=oldCost+grad'*(newX-y)+norm(newX-y)^2*obj.t/2)
                    break;
                else obj.t=obj.t/obj.stepShrnk;
                end
            end
            obj.alpha = newX;

            obj.s = obj.softThresh(...
                obj.Psit(obj.alpha+obj.y1),...
                obj.u/(obj.rho));
            obj.Psi_s = obj.Psi(obj.s);

            obj.y1 = obj.y1 - (obj.Psi_s-obj.alpha);

            obj.fVal(obj.n+1) = sum(abs(obj.Psit(obj.alpha)));
            obj.cost = obj.fVal(:)'*obj.coef(:);
        end
    end
end
