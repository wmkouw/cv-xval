function [MSE,minLambda,Lambda,S,W,params] = exp_csxval_synth(varargin)
% Experiment with regularization parameter estimation on synthetic data
%
% Wouter Kouw
% Last update: 2017-04-24

% Add utility functions to path
addpath(genpath('../util'));
if isempty(which('sampleDist')); error('Please add sampleDist to the addpath'); end

% Parse
p = inputParser;
addOptional(p, 'theta_X_yn', [-1 1]);
addOptional(p, 'theta_X_yp', [ 1 1]);
addOptional(p, 'S', [1 2 3 4].^2);
addOptional(p, 'Lambda', linspace(-100,500,101));
addOptional(p, 'N', 100);
addOptional(p, 'M', 100);
addOptional(p, 'nR', 10);
addOptional(p, 'domainLimits', [-20 20]);
addOptional(p, 'save', false);
addOptional(p, 'saveName', 'results_exp_cvxval_synth');
addOptional(p, 'iwe', 'true');
parse(p, varargin{:});

% Source parameters
params.X_yn = p.Results.theta_X_yn;
params.X_yp = p.Results.theta_X_yp;

% Source domain
pX_yn = @(x) normpdf(x, params.X_yn(1), sqrt(params.X_yn(2)));
pX_yp = @(x) normpdf(x, params.X_yp(1), sqrt(params.X_yp(2)));
pyn = 1./2;
pyp = 1./2;
pX = @(x) pX_yn(x)*pyn + pX_yp(x)*pyp;

% Lambda range
Lambda = p.Results.Lambda;
nLa = length(Lambda);

% Target variance range
S = p.Results.S;
nS = length(S);

% Set domain limits
d = linspace(p.Results.domainLimits(1),p.Results.domainLimits(2), 201);

% Preallocate variables
W = cell(nS,p.Results.nR);
MSE.V = zeros(nS,nLa,p.Results.nR);
MSE.W = zeros(nS,nLa,p.Results.nR);
MSE.Z = zeros(nS,nLa,p.Results.nR);
minl.V = zeros(nS,p.Results.nR);
minl.W = zeros(nS,p.Results.nR);
minl.Z = zeros(nS,p.Results.nR);

for r = 1:p.Results.nR
    % Report progress
	fprintf('Running repeat %d / %d \n', r, p.Results.nR);
        
    for s = 1:nS
        
        % Target variance parameterse
        params.Z_yn = [-1 S(s)];
        params.Z_yp = [ 1 S(s)];
        pZ_yn = @(z) normpdf(z, params.Z_yn(1), sqrt(params.Z_yn(2)));
        pZ_yp = @(z) normpdf(z, params.Z_yp(1), sqrt(params.Z_yp(2)));
        pZ = @(z) (pZ_yn(z).*pyn + pZ_yp(z).*pyp);
        
        % Generate class-conditional distributions and sample sets
        [Vy_n,Vy_p,Zy_n,Zy_p] = gen_covshift(pZ, ...
            'ubX', 2./sqrt(2*pi), 'ubZ', 2./sqrt(2*pi*S(s)),  ...
            'theta_Xyn', params.X_yn,'theta_Xyp', params.X_yp, ...
            'N', p.Results.N, 'M', p.Results.M, ...
            'xl', p.Results.domainLimits, 'zl', p.Results.domainLimits);
        
        % Sample training data
        Xy_n = sampleDist(pX_yn, 2./sqrt(2*pi), round(p.Results.N.*pyn), p.Results.domainLimits, false);
        Xy_p = sampleDist(pX_yp, 2./sqrt(2*pi), round(p.Results.N.*pyp), p.Results.domainLimits, false);
        
        % Concatenate to source validation set 
        V = [Vy_n; Vy_p];
        yV = [-ones(size(Vy_n,1),1); ones(size(Vy_p,1),1)];
        
        % Concatenate to target validation set
        Z = [Zy_n; Zy_p];
        yZ = [-ones(size(Zy_n,1),1); ones(size(Zy_p,1),1)];
        
        % Concatenate to source training set
        X = [Xy_n; Xy_p];
        yX = [-ones(size(Xy_n,1),1); ones(size(Xy_p,1),1)];
        
        % Obtain importance weights
        switch lower(p.Results.iwe)
            case 'none'
                W{s,r} = ones(size(V,1),1);
            case 'true'
                W{s,r} = pZ(V)./pX(V);
            case 'gauss'
                W{s,r} = iwe_Gauss(V,Z, 'lambda', 0);
            case 'kmm'
                W{s,r} = iwe_KMM(V,Z, 'theta', 1, 'B', 1000);
            case 'kliep'
                W{s,r} = iwe_KLIEP(V,Z, 'sigma', 0);
            case 'nnew'
                W{s,r} = iwe_NNeW(V,Z, 'Laplace', 1);
            otherwise
                error(['Unknown importance weight estimator']);
        end
        
        % Augment data
        Xa = [X ones(size(X,1),1)];
        Va = [V ones(size(V,1),1)];
        Za = [Z ones(size(Z,1),1)];
        
        % Loop over regularization parameter values
        for l = 1:nLa
            
            % Analytical solution to regularized least-squares classifier
            theta = (Xa'*Xa + Lambda(l)*eye(2))\Xa'*yX;
            
            % Mean squared error curves
            MSE.V(s,l,r) = mean((Va*theta - yV).^2,1);
            MSE.W(s,l,r) = mean((Va*theta - yV).^2.*W{s,r},1);
            MSE.Z(s,l,r) = mean((Za*theta - yZ).^2,1);
        end
        
        % Minima of mean squared error curves
        [~,minl.V(s,r)] = min(MSE.V(s,:,r), [], 2);
        [~,minl.W(s,r)] = min(MSE.W(s,:,r), [], 2);
        [~,minl.Z(s,r)] = min(MSE.Z(s,:,r), [], 2);
    end
end

% Arg min of mean squared error curves
minLambda.V = Lambda(minl.V);
minLambda.W = Lambda(minl.W);
minLambda.Z = Lambda(minl.Z);

% Write to file
if p.Results.save
    fn = [p.Results.saveName '.mat'];
    disp(['Done. Writing to ' fn]);
    save(fn, 'MSE', 'minLambda', 'Lambda', 'theta', 'S', 'W');
end

end



