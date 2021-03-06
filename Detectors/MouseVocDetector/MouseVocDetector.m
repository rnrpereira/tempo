classdef MouseVocDetector < FeaturesDetector
    
    properties
        recording
        
        NW
        K
        PVal
        NFFT

        FreqLow
        FreqHigh
        ConvWidth
        ConvHeight
        MinObjArea

        MergeHarmonics
        MergeHarmonicsOverlap
        MergeHarmonicsRatio
        MergeHarmonicsFraction

        MinLength
    end
    
    
    methods(Static)
        
        function n = typeName()
            n = 'Mouse Vocalization';
        end
        
        function ft = possibleFeatureTypes()
            ft = {'Vocalization'};
        end
        
        function initialize()
            %classFile = mfilename('fullpath');
            %parentDir = fileparts(classFile);
            %addpath(genpath(fullfile(parentDir, 'chronux')));
        end
        
    end
    
    
    methods
        
        function obj = MouseVocDetector(recording)
            obj = obj@FeaturesDetector(recording);
            obj.NW = getpref('Tempo', 'NW', 3);
            obj.K = getpref('Tempo', 'K', 5);
            obj.PVal = getpref('Tempo', 'PVal', 0.01);
            obj.NFFT = getpref('Tempo', 'NFFT', [32 64 128]);
            obj.FreqLow = getpref('Tempo', 'FreqLow', 20e3);
            obj.FreqHigh = getpref('Tempo', 'FreqHigh', 120e3);
            obj.ConvWidth = getpref('Tempo', 'ConvWidth', 0.001);
            obj.ConvHeight = getpref('Tempo', 'ConvHeight', 1300);
            obj.MinObjArea = getpref('Tempo', 'MinObjArea', 18.75);
            obj.MergeHarmonics = getpref('Tempo', 'MergeHarmonics', 0);
            obj.MergeHarmonicsOverlap = getpref('Tempo', 'MergeHarmonicsOverlap', 0);
            obj.MergeHarmonicsRatio = getpref('Tempo', 'MergeHarmonicsRatio', 0);
            obj.MergeHarmonicsFraction = getpref('Tempo', 'MergeHarmonicsFraction', 0);
            obj.MinLength = getpref('Tempo', 'MinLength', 0);
        end
        
        
        function s = settingNames(~)
            s = {'NW', 'K', 'PVal', 'NFFT', ...
                 'FreqLow', 'FreqHigh', 'ConvWidth', 'ConvHeight', 'MinObjArea', ...
                 'MergeHarmonics', 'MergeHarmonicsOverlap', 'MergeHarmonicsRatio', 'MergeHarmonicsFraction', ...
                 'MinLength'};
        end
        
        
        function setRecording(obj, recording)
            setRecording@FeaturesDetector(obj, recording);
        end
        
        
        function features = detectFeatures(obj, timeRange)

            persistent sampleRate2 NFFT2 NW2 K2 PVal2 timeRange2
            
            features = {};
            
            [p,n,e]=fileparts(obj.recording{1}.filePath);

            if(isempty(sampleRate2) || (sampleRate2~=obj.recording{1}.sampleRate) || ...
                isempty(NFFT2) || length(NFFT2)~=length(obj.NFFT) || any(NFFT2~=obj.NFFT) || ...
                isempty(NW2) || (NW2~=obj.NW) || ...
                isempty(K2) || (K2~=obj.K) || ...
                isempty(PVal2) || (PVal2~=obj.PVal) || ...
                isempty(timeRange2) || any(timeRange2~=timeRange(1:2)))
              delete([fullfile(p,n) '*tmp*.ax']);
              nsteps=(2+length(obj.NFFT));
              filename = fullfile(p,n);
              if(strcmpi(e,'.wav')||strcmpi(e,'.bin'))
                filename = [filename e];
              end
              for i=1:length(obj.NFFT)
                obj.updateProgress('Running multitaper analysis on signal...', (i-1)/nsteps);
                ax1(obj.recording{1}.sampleRate, obj.NFFT(i), obj.NW, obj.K, obj.PVal,...
                    filename,['tmp' num2str(i)],...
                    timeRange(1), timeRange(2));
              end

              delete([tempdir '*tmp*.ax']);
              movefile([fullfile(p,n) '*tmp*.ax'],tempdir);
            else
              nsteps=2;
            end

            tmp=dir(fullfile(tempdir,[n '*tmp*.ax']));
            cellfun(@(x) regexp(x,'.*tmp.\.ax'),{tmp.name});
            tmp=tmp(logical(ans));
            hotpixels={};
            for i=1:length(tmp)
               foo=h5read(fullfile(tempdir,tmp(i).name),'/hotPixels');
               NFFT=h5readatt(fullfile(tempdir,tmp(i).name),'/hotPixels','NFFT');
               FS=h5readatt(fullfile(tempdir,tmp(i).name),'/hotPixels','FS');
               dT=NFFT/FS/2;
               dF=FS/NFFT/10;  % /10 for brown-puckette
               foo(:,1)=foo(:,1)*dT;
               hotpixels{i}={foo(:,[1 2 4]), dT, dF};
            end

            sampleRate2=obj.recording{1}.sampleRate;
            NFFT2=obj.NFFT;
            NW2=obj.NW;
            K2=obj.K;
            PVal2=obj.PVal;
            timeRange2=timeRange(1:2);

            %rmdir([fullfile(tempdir,n) '-out*'],'s');
            tmp=dir([fullfile(tempdir,n) '-out*']);
            if(~isempty(tmp))
              rmdir([fullfile(tempdir,n) '-out*'],'s');
            end

            obj.updateProgress('Heuristically segmenting syllables...', (nsteps-2)/nsteps);
            tmp=dir(fullfile(tempdir,[n '*tmp*.ax']));
            ax_files = cellfun(@(x) fullfile(tempdir,x), {tmp.name}, 'uniformoutput', false);
            ax2(obj.FreqLow, obj.FreqHigh, [obj.ConvHeight obj.ConvWidth], obj.MinObjArea, ...
                obj.MergeHarmonics, obj.MergeHarmonicsOverlap, obj.MergeHarmonicsRatio, obj.MergeHarmonicsFraction,...
                obj.MinLength, [], ax_files, fullfile(tempdir,n));

            obj.updateProgress('Adding features...', (nsteps-1)/nsteps);
            tmp=dir([fullfile(tempdir,n) '.voc*']);
            voclist=load(fullfile(tempdir,tmp.name));

            for i = 1:size(voclist, 1)
                if(i==1)
                  feature = Feature('Vocalization', voclist(i,1:4), ...
                                    'HotPixels', hotpixels);
                else
                  feature = Feature('Vocalization', voclist(i,1:4));
                end
                features{end + 1} = feature; %#ok<AGROW>
            end
        end
        
    end
    
end
