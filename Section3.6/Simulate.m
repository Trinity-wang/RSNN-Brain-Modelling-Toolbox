function [firings, firings2, boxes] = Simulate(layer,layer2,time,Ne_,Ni_,Ne_per_module)

  
   % The number of interations to settle for wrong initial conditions
   epochs = 2;
   
   x0_ = load('EEGDATASET.mat');
   x1 = [];
   y1 = [];
   y2 = [];
   dt = 0.1526531;
   boxes = [];
   %Uncomment the line below for trying many EEG channels (also the corresponding end)
   %for lll=1:1:32
   close all;
   x0 = x0_.data1{1,1}(14,:,1);
   data = double(x0);
   % Set the sampling frequency
   Fs = 128;
   % Set the frequency of optimization
   step = 2;
   % Upsample the EEG signal
   data = interp(data(1:end),50); % increase data samples by 50 times
   % Set the target signal to be modelled
   target_signal = data;
   N = Ne_+Ni_;
   
   % Save the state-space trajectory of optimal weight matrices
   store_mats = zeros(N, ceil(length(target_signal)/step));
   % Store the collective voltage in this array
   LFP=zeros(length(target_signal),3);
   track_WEIGHTS_std = zeros(length(target_signal)/step,1);
   track_WEIGHTS_avg = zeros(length(target_signal)/step,1);
   
   Ne=Ne_;                Ni=Ni_;                   N=Ne+Ni;
    

   tic
   % Uncomment for trying different maximum axonal conductance delays
   %for ll=0:1:20
   %Dmax = ll;
   for num=1:epochs 
    Dmax = 15; % maximum propagation delay
    % SIMULATE
    % Initialise layers
    fprintf('EPOCH: %.1f \n', num);
    rng(2);
    
    %% TASK NETWORK
    z_ = ones(0.8*N,1);
    %Storage variables for synapse integration  
    IPSC = zeros(N,1); %post synaptic current 
    h = zeros(N,1); 
    r = zeros(N,1);
    hr = zeros(N,1);
    tr = 2;  %synaptic rise time 
    td = 20; %decay time 
    k = min(size(target_signal)); %used to get the dimensionality of the approximant correctly.  Typically will be 1 unless you specify a k-dimensional target function.  
    z = zeros(k,1);  %initial estimated EEG signal
    if num<epochs
        BPhi = zeros(N,k); %initial decoder.  Best to keep it at 0.
    end
    Pinv = eye(N)*2200; %initial correlation matrix, coefficient is the regularization constant as well 
    current = zeros(length(target_signal),k);  %store the approximant 
    RECB = zeros(length(target_signal),5); %store the decoders 
    REC = zeros(length(target_signal),10); %Store voltage and adaptation variables for plotting 
    errors_train = zeros(length(data),1);
    %%
    
    %% TARGET NETWORK
    IPSC2 = zeros(N,1); %post synaptic current 
    h2 = zeros(N,1); 
    r2 = zeros(N,1);
    hr2 = zeros(N,1);
    tr2 = 2;  %synaptic rise time 
    td2 = 20;%((17*randi([0,20]))+50)/2;
    k2 = min(size(target_signal)); %used to get the dimensionality of the approximant correctly.  Typically will be 1 unless you specify a k-dimensional target function.  
    z2 = zeros(k,1);  %initial approximant
    BPhi2 = zeros(N,k); %initial decoder.  Best to keep it at 0. 
    Pinv2 = eye(N)*2200; %initial correlation matrix, coefficient is the regularization constant as well 
    current2 = zeros(length(target_signal),k);  %store the approximant 
    RECB2 = zeros(length(target_signal),5); %store the decoders 
    REC2 = zeros(length(target_signal),10); %Store voltage and adaptation variables for plotting 
    %%


    N1 = layer{1}.rows;
    M1 = layer{1}.columns;
    MN = M1*N1;

    N2 = layer{2}.rows;
    M2 = layer{2}.columns;
    
    N1_2 = layer2{1}.rows;
    M1_2 = layer2{1}.columns;
    MN_2 = M1_2*N1_2;

    N2_2 = layer2{2}.rows;
    M2_2 = layer2{2}.columns;

    
    Tmax = length(data); % simulation time per episode
    
    for lr=1:length(layer)
       layer{lr}.v = -65*ones(layer{lr}.rows,layer{lr}.columns);
       layer{lr}.u = layer{lr}.b.*layer{lr}.v;
       layer{lr}.firings = [];
       
       layer2{lr}.v = -65*ones(layer2{lr}.rows,layer2{lr}.columns);
       layer2{lr}.u = layer2{lr}.b.*layer2{lr}.v;
       layer2{lr}.firings = [];
    end
    
    waiting = waitbar(0,'Please wait...');
    s = clock;

    for t = 1:Tmax
      
      if mod(t, step)==1 && num==epochs
        BPhi = store_mats(:,floor(t/step)+1);
      end
    
      if mod(t, step)==0 && num<epochs
        store_mats(:,t/step) = BPhi;
      end
      
      % Deliver a Poisson spike stream
      lambda = 0.01; %
    
      layer{1}.I = 15*(poissrnd(lambda,N1,M1) > 0);
      layer{2}.I = zeros(N2,M2);
     
      
      layer2{1}.I = 15*(poissrnd(lambda,N1_2,M1_2) > 0);
      layer2{2}.I = zeros(N2_2,M2_2);
      
      % Deliver a single spike to a single neuron
      if t == 1
         i = ceil(rand*N1);
         j = ceil(rand*M1);
         layer{1}.I(i,j) = 15;
         
         i_2 = ceil(rand*N1_2);
         j_2 = ceil(rand*M1_2);
         layer2{1}.I(i_2,j_2) = 15;
      end
      
      % Update all the neurons
      v_1=0;
      v_2=0;
      v_1_2=0;
      v_2_2=0;

      for lr=1:length(layer)
         if lr==1
            [layer, v_1] = IzNeuronUpdate(layer,lr,t,Dmax,v_1);
            [layer2, v_1_2] = IzNeuronUpdate(layer2,lr,t,Dmax,v_1_2);
         else
            [layer,v_2] = IzNeuronUpdate(layer,lr,t,Dmax,v_2);
            [layer2,v_2_2] = IzNeuronUpdate(layer2,lr,t,Dmax,v_2_2);
         end
      end 
    v_task = [v_1; v_2];
    v_target = [v_1_2; v_2_2];

    firings = layer{1}.firings;
    firings2 = layer{2}.firings;
    fired = [firings; firings2];
    
    firings_2 = layer2{1}.firings;
    firings2_2 = layer2{2}.firings;
    fired2 = [firings_2; firings2_2];
    
    %synapse for double exponential
    I = [layer{1}.I; layer{2}.I];
    IPSC = I*exp(-dt/tr) + h*dt;
    I2 = [layer2{1}.I; layer2{2}.I];
    IPSC2 = I2*exp(-dt/tr2) + h2*dt;
    
    h = h*exp(-dt/td) + IPSC*(~isempty(fired))/(tr*td);  %Integrate the current

    r = r*exp(-dt/tr) + hr*dt; 
    
    hr = hr*exp(-dt/td) + (v_task>=30)/(tr*td);
    

    %IPSC2 = IPSC2*exp(-dt/tr2) + h2*dt;
    I2 = [layer2{1}.I; layer2{2}.I];
    h2 = h2*exp(-dt/td2) + IPSC2*(~isempty(fired2))/(tr2*td2);  %Integrate the current

    r2 = r2*exp(-dt/tr2) + hr2*dt; 
    
    hr2 = hr2*exp(-dt/td2) + (v_target>=30)/(tr2*td2);
    
    z2 = BPhi2'*r2; %estimated EEG for TARGET NET
    err2 = z2 - target_signal(:,t); %error 
    
    if num == epochs
        LFP(t,1)=sum(v_task(1:0.8*N));         % sum of voltages of excitatory per ms 
        LFP(t,2)=sum(v_task(0.8*N+1:end));         % sum of voltages of excitatory per ms
        LFP(t,3)=sum(v_task(:));         % sum of voltages of excitatory per ms 
    end
     
    z = BPhi'*r; %estimated EEG for TASK NET 
    err = z - target_signal(:,t)-rand(min(size(r2)))*z2; %error
    if num == epochs
        errors_train(t) = err;
    end
     %% RLS 
     if mod(t,step)==0 && num<epochs
           cd = Pinv*r;
           BPhi = BPhi - (cd*err');
           Pinv = Pinv -((cd)*(cd'))/( 1 + (r')*(cd));
           track_WEIGHTS_std(t/step) = std(BPhi);
           track_WEIGHTS_avg(t/step) = mean(BPhi);
     end 
     
 %   REC(i,:) = [v(1:5)',u(1:5)'];  
    current(t,:) = z';
%    RECB(i,:)=BPhi(1:5);

    if mod(t,9600)==0 
        drawnow
        figure(1)
        plot(target_signal(1:t),'k','LineWidth',2), hold on
        plot(current(1:t),'r--','LineWidth',2), hold off
        xlabel('Timestep');
        ylabel('Amplitude, $\mu$V','Interpreter','latex');
        legend('Target EEG Signal', 'Modelled EEG');
        set(gca,'FontSize',15);
        %ylim([-80 80]);
        grid on;
        if num < epochs
            figure(3);
            plot(track_WEIGHTS_std(1:end),'b','Linewidth',2);
            xlabel('Timestep');
            ylabel('$\Delta$W (s.d. in Weight updates)','interpreter','latex');
            grid on;
            figure(4);
            plot(track_WEIGHTS_avg(1:end),'b','Linewidth',2);
            xlabel('Timestep');
            ylabel('$\Delta$W (Mean Weight update)','interpreter','latex');
            grid on;
        end
       if num == epochs
            figure(20);
            plot(LFP,'Linewidth', 2);
            legend('Excitatory','Inhibitory','All');
            ylabel('mV');
            xlabel('Timestep');
            set(gca,'FontSize',15);
            grid on;
        end
    end   
    
    waiting = waitbar(t/Tmax,waiting,['Please wait...']);
    
    end 
    
    
   end
    toc
   summation = 0;
    for i=1:1:length(errors_train)
        summation = summation + errors_train(i)^2;
    end
    boxes = [boxes errors_train];
    rmse = sqrt(mean(summation));
    MFR = MeanFiringRate(firings,50,20,Ne_per_module);    
    complexity = NeuralComplexity(MFR);
    fprintf('Dmax: %.1f, RMSE: %.1f, Complexity: %.5f \n', Dmax, rmse, complexity);
    %x1 = [x1 Dmax];
    %yi = [y1 rmse];
    %y2 = [y2 complexity];
   %end
   
% Plots the boxplot of selected channels
%boxplot(boxes);

% Plots the dynamical complexity and RMSE for varying Dmax
%figure;
%x = 0:1:20;
%plot(x,y1, 'k', 'Linewidth', 2); hold on;
%plot(x,y2, 'r', 'Linewidth', 2); hold off;

%xticks(x);
%xlabel('Maximum delay (ms)');
%ylabel('RMSE, $\mu$V', 'Interpreter', 'latex');
%set(gca,'FontSize',15);
%set(gca, 'YScale', 'log');
%legend('Dynamical Complexity','RMSE', 'Location', 'Best');
%grid on;