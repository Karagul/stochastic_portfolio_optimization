%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% STOCHASTIC PROGRAMMING
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% the purpose of this project is to implement a two-stage stochastic linear
% program which solves a tuition investment-matching strategy.

% authors: Matthew Reiter and Daniel Kecman
% date: april 11, 2018

clc
clear all
format long

% note that this project is compatible with MATLAB 2015.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1. read input files
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% load the stock weekly prices and factors weekly returns
data = readtable('price_data.csv');
data.Properties.RowNames = cellstr(datetime(data.Date));
data = data(:,2:size(data,2));

% n represents the number of stocks that we have
n = size(data,2);

% identify the tickers and the dates 
tickers = data.Properties.VariableNames';
dates = datetime(data.Properties.RowNames);

% calculate the stocks' yearly returns
prices  = table2array(data);
returns = (prices(2:end,:) - prices(1:end-1,:)) ./ prices(1:end-1,:);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 2. estimation of mean and variance
%   - we use historial data spanning a year from 2014-01-03 to 2014-12-26
%   - we use the geometric mean for stock returns and from this we formulate
%   the covariance matrix
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% calibration start data and end data
cal_start = datetime('2014-01-03');
cal_end = cal_start + calmonths(12) - days(2);

cal_returns = returns(cal_start <= dates & dates <= cal_end,:);
current_prices = table2array(data((cal_end - days(7)) <= dates & dates <= cal_end,:))';

% calculate the geometric mean of the returns of all assets
mu = 52*(geomean(cal_returns+1)-1)'
cov = 52*cov(cal_returns);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 3. scenario generation
%   - we use two methods to generate scenarios, seperate for the scenario's
%   governing the asset returns and for the matched liabilities
%   - for asset returns, we model the stock price as a Geometric Brownian
%   Motion and do a Monte Carlo simulation to estimate stock returns for
%   our investment period spanning a year from 2015-01-02 to 2015-12-31
%   - for our liabilties, we sample from a normal distribution
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% we need the correlation matrix to simulate the correlated prices of 
% portfolio
rho = corrcov(cov);

% we take the cholesky factorization of the correlation matrix
L = chol(rho, 'lower');

% define the number of randomized scenarios to sample for
S = 5;

% our simulated asset prices and returns
sim_price = zeros(n,S);
sim_returns = zeros(n,S);

% our scenario liabilities
sim_liabilities = zeros(S,1);

% we have yearly estimates for returns and we wish to simulate the
% price path after six months using monthly time-steps
dt = 1/252;

% setting the random seed so that our random draws are consistent across testing
rng(1);

tuition = 17000;

for i=1:S

    % our random correlated pertubations
    epsilon = L * normrnd(0,1,[n,1]);
    
    % randomize our liabilities
    sim_liabilities(i) = tuition + normrnd(500,200);

    % calculate our simulated prices
    sim_price(:,i) = current_prices .* exp((mu - 0.5 * diag(cov))*dt + sqrt(dt)*sqrt(diag(cov)) .* epsilon);  

    % calculate our simulated returns
    sim_returns(:,i) = (sim_price(:,i) - current_prices) ./ current_prices;
end

sim_returns
sim_liabilities
mu

X = 1:n;
Y = 1:S;
mesh(sim_price);
title('Simulated Prices of Holding Assets', 'FontSize', 14)
ylabel('Asset','interpreter','latex','FontSize',12);
xlabel('Scenario','interpreter','latex','FontSize',12);
zlabel('Asset Price','interpreter','latex','FontSize',12);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 4. stochastic optimization
%   - implementation of the above scenarios, incorporating second stage and
%   first stage constraints
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% take uniform probability for each scenario
p = 1/S;

% we have an initial budget of 17,500
B = 17500;

% the benefit of running a surplus will be a 1 and the cost of running a
% shortfall will be -2
surplus = -1;
shortfall = 2;

% formulate our objective function
f = [ones(1,n) repmat(p*[surplus shortfall], 1, S)]';

% dealing with our first-stage constraints
A = [ones(1,n) zeros(1,2*S)];
b = B;

% handling our second stage constraints
temp = [-1 1];
temp_r = repmat(temp, 1, S);
temp_c = mat2cell(temp_r, size(temp,1), repmat(size(temp,2),1,S));
con = blkdiag(temp_c{:});

Aeq = [(sim_returns+1)' con];
beq = sim_liabilities;

lb = zeros(n+2*S,1);
ub = [];

[stochastic, sto_value] = linprog(f, A, b, Aeq, beq, lb, ub)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 5. value of the stochastic solution
%   - based on the expected values of the returns and the liability
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% first we determine the value of our deterministic problem considering
% only the expected returns and liabilities

% formulate our objective function
f = [ones(1,n) surplus shortfall]';

% dealing with our first-stage constraints
A = [ones(1,n) 0 0];
b = B;

Aeq = [(mu+1)' -1 1];
beq = tuition+500;
 
lb = zeros(n+2,1);
ub = [];
 
[deterministic, det_value] = linprog(f, A, b, Aeq, beq, lb, ub)

% now we solve the stochastic problem with the first stage variables as
% determined from our deterministic model

% formulate our objective function
f = repmat(p*[surplus shortfall], 1, S)';

% no first stage constraints need to be optimized since we are using the
% first stage constraints from the deterministics model
A = [];
b = [];

% constraints tied only to our recourse variables
temp = [-1 1];
temp_r = repmat(temp, 1, S);
temp_c = mat2cell(temp_r, size(temp,1), repmat(size(temp,2),1,S));
Aeq = blkdiag(temp_c{:});

% we update what the required liabilties must be with the given first stage
% variables set
beq = sim_liabilities - (sim_returns+1)'*deterministic(1:n);
 
lb = zeros(2*S,1);
ub = [];
 
[recourse, recourse_value] = linprog(f, A, b, Aeq, beq, lb, ub)
vss = recourse_value + sum(deterministic(1:n)) - sto_value

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 6. tracking performance of stochastic model 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% testing period start date and end date
test_start = cal_end + days(1);
test_end = test_start + calmonths(12) - days(2);

% subset the prices corresponding to the current out-of-sample test period.
period_prices = table2array(data(test_start <= dates & dates <= test_end,:));

% the current value of our stock portfolio is the sum of all the wealth we
% allocate to each stock
current_value = sum(stochastic(1:n));

% get the prices of our assets at the beginning of our tracked period
current_prices = table2array(data((test_start) <= dates & dates <= test_start,:))';

% calculate the number of shares of each stock to purchase
shares = stochastic(1:n) ./ current_prices;
        
% weekly portfolio value during the out-of-sample window
portfolio_value = period_prices * shares

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7. plot tracked portfolio results
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
plot_dates = dates(test_start <= dates);

fig1 = figure(1);

plot(plot_dates, portfolio_value)

datetick('x','dd-mmm-yyyy','keepticks','keeplimits');
set(gca,'XTickLabelRotation',30);
title('Portfolio Value', 'FontSize', 14)
ylabel('Value','interpreter','latex','FontSize',12);

% define the plot size in inches
set(fig1,'Units','Inches', 'Position', [0 0 8, 5]);
pos1 = get(fig1,'Position');
set(fig1,'PaperPositionMode','Auto','PaperUnits','Inches', 'PaperSize',[pos1(3), pos1(4)]);

% save the figure
print(fig1,'stochastic-portfolio-value','-dpng','-r0');