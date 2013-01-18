classdef AnalysisController < handle
    
    properties
        figure
        
        recordings = Recording.empty()
        reporters = {}
        
        duration = 300
        zoom = 1
        
        videoPanels = {}
        otherPanels = {}
        timeIndicatorPanel = []
        
        timeSlider
        
        toolbar
        zoomOutTool
        playMediaTool
        pauseMediaTool
        detectPopUpTool
        
        timeLabelFormat = 1     % default to displaying time in minutes and seconds
        
        panelSelectingTime
        
        isPlayingMedia = false
        playTimer
        mediaTimer
        mediaTimeSync
        
        detectorClassNames
        detectorTypeNames
        importerClassNames
        importerTypeNames
        
        importing = false
        recordingsToAdd = Recording.empty()
        
        showWaveforms
        showSpectrograms
        showFeatures
    end
    
    properties (SetObservable)
        % The analysis panels will listen for changes to these properties.
        displayedTime = 0       % The time that all of the non-video panels should center their display on (in seconds).
        timeWindow = 0          % The width of the time window the non-video panels should display (in seconds).
        currentTime = 0         % The time point currently being played (in seconds).
        selectedTime = [0 0]    % The range of time currently selected (in seconds).  The two values will be equal if there is a point selection.
        windowSize = 0
        freqMin = 0
        freqMax = 0
    end
    
    %                   On change update:                           Can be changed by:
    % displayedTime     other panels, time slider                   time slider, key press, player
    % timeWindow        other panels                                toolbar icons, key press
    % currentTime       other panels, video panels, time label      axes click, key press, player
    % selectedTime      other panels, time label                    axes click, key press
    
    methods
        
        function obj = AnalysisController()
            obj.showWaveforms = getpref('SongAnalysis', 'ShowWaveforms', true);
            obj.showSpectrograms = getpref('SongAnalysis', 'ShowSpectrograms', true);
            obj.showFeatures = getpref('SongAnalysis', 'ShowFeatures', true);
            
            obj.figure = figure('Name', 'Song Analysis', ...
                'NumberTitle', 'off', ...
                'Toolbar', 'none', ...
                'MenuBar', 'none', ...
                'Position', getpref('SongAnalysis', 'MainWindowPosition', [100 100 400 200]), ...
                'Color', [0.4 0.4 0.4], ...
                'Renderer', 'opengl', ...
                'ResizeFcn', @(source, event)handleResize(obj, source, event), ...
                'KeyPressFcn', @(source, event)handleKeyPress(obj, source, event), ...
                'KeyReleaseFcn', @(source, event)handleKeyRelease(obj, source, event), ...
                'CloseRequestFcn', @(source, event)handleClose(obj, source, event), ...
                'WindowButtonDownFcn', @(source, event)handleMouseButtonDown(obj, source, event), ...
                'WindowButtonMotionFcn', @(source, event)handleMouseMotion(obj, source, event), ...
                'WindowButtonUpFcn', @(source, event)handleMouseButtonUp(obj, source, event)); %#ok<CPROP>
            
            if isdeployed && exist(fullfile(ctfroot, 'Detectors'), 'dir')
                % Look for the detectors in the CTF archive.
                parentDir = ctfroot;
            else
                % Look for the detectors relative to this .m file.
                analysisPath = mfilename('fullpath');
                parentDir = fileparts(analysisPath);
            end
            
            [obj.detectorClassNames, obj.detectorTypeNames] = findPlugIns(fullfile(parentDir, 'Detectors'));
            [obj.importerClassNames, obj.importerTypeNames] = findPlugIns(fullfile(parentDir, 'Importers'));
            
            addpath(fullfile(parentDir, 'AnalysisPanels'));
            
            addpath(fullfile(parentDir, 'export_fig'));
            
            obj.timeIndicatorPanel = TimeIndicatorPanel(obj);
            
            obj.createToolbar();
            
            % Create the scroll bar that lets the user scrub through time.
            obj.timeSlider = uicontrol('Style', 'slider',...
                'Min', 0, ...
                'Max', obj.duration, ...
                'Value', 0, ...
                'Position', [1 1 400 16], ...
                'Callback', @(source, event)handleTimeSliderChanged(obj, source, event));
            if verLessThan('matlab', '7.12.0')
                addlistener(obj.timeSlider, 'Action', @(source, event)handleTimeSliderChanged(obj, source, event));
            else
                addlistener(obj.timeSlider, 'ContinuousValueChange', @(source, event)handleTimeSliderChanged(obj, source, event));
            end
            addlistener(obj, 'displayedTime', 'PostSet', @(source, event)handleTimeWindowChanged(obj, source, event));
            addlistener(obj, 'timeWindow', 'PostSet', @(source, event)handleTimeWindowChanged(obj, source, event));
            
            obj.arrangePanels();
            
            % Set up a timer to fire 30 times per second when the media is being played.
            obj.mediaTimer = timer('ExecutionMode', 'fixedRate', 'TimerFcn', @(timerObj, event)handleMediaTimer(obj, timerObj, event), 'Period', round(1.0 / 30.0 * 1000) / 1000);
        end
        
        
        function createToolbar(obj)
            % Open | Zoom in Zoom out | Play Pause | Find features | Save features Save screenshot | Show/hide waveforms Show/hide features Toggle time format
            obj.toolbar = uitoolbar(obj.figure);
            
            iconRoot = 'Icons';
            defaultBackground = get(0, 'defaultUicontrolBackgroundColor');
            
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'file_open.png'), 'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'openFile', ...
                'CData', iconData, ...
                'TooltipString', 'Open audio/video files or import features',... 
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handleOpenFile(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'tool_zoom_in.png'), 'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'zoomIn', ...
                'CData', iconData, ...
                'TooltipString', 'Zoom in',... 
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handleZoomIn(obj, hObject, eventdata));
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'tool_zoom_out.png'), 'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'zoomOut', ...
                'CData', iconData, ...
                'TooltipString', 'Zoom out',... 
                'ClickedCallback', @(hObject, eventdata)handleZoomOut(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(iconRoot, 'play.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.playMediaTool = uipushtool(obj.toolbar, ...
                'Tag', 'playMedia', ...
                'CData', iconData, ...
                'TooltipString', 'Play audio/video recordings',... 
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handlePlayMedia(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'pause.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.pauseMediaTool = uipushtool(obj.toolbar, ...
                'Tag', 'pauseMedia', ...
                'CData', iconData, ...
                'TooltipString', 'Pause audio/video recordings',... 
                'ClickedCallback', @(hObject, eventdata)handlePauseMedia(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(iconRoot, 'detect.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.detectPopUpTool = uisplittool('Parent', obj.toolbar, ...
                'Tag', 'detectFeatures', ...
                'CData', iconData, ...
                'TooltipString', 'Detect features',... 
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handleDetectFeatures(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'file_save.png'),'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'saveFeatures', ...
                'CData', iconData, ...
                'TooltipString', 'Save all features',...
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handleSaveAllFeatures(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'screenshot.png'), 'BackgroundColor', defaultBackground)) / 255;
            uipushtool(obj.toolbar, ...
                'Tag', 'saveScreenshot', ...
                'CData', iconData, ...
                'TooltipString', 'Save a screenshot',...
                'ClickedCallback', @(hObject, eventdata)handleSaveScreenshot(obj, hObject, eventdata));
            
            states = {'off', 'on'};
            iconData = double(imread(fullfile(iconRoot, 'waveform.png'), 'BackgroundColor', defaultBackground)) / 255;
            uitoggletool(obj.toolbar, ...
                'Tag', 'showHideWaveforms', ...
                'CData', iconData, ...
                'State', states{obj.showWaveforms + 1}, ...
                'TooltipString', 'Show/hide the waveform(s)',... 
                'Separator', 'on', ...
                'OnCallback', @(hObject, eventdata)handleToggleWaveforms(obj, hObject, eventdata), ...
                'OffCallback', @(hObject, eventdata)handleToggleWaveforms(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'spectrogram.png'), 'BackgroundColor', defaultBackground)) / 255;
            uitoggletool(obj.toolbar, ...
                'Tag', 'showHideSpectrograms', ...
                'CData', iconData, ...
                'State', states{obj.showSpectrograms + 1}, ...
                'TooltipString', 'Show/hide the spectrogram(s)',... 
                'OnCallback', @(hObject, eventdata)handleToggleSpectrograms(obj, hObject, eventdata), ...
                'OffCallback', @(hObject, eventdata)handleToggleSpectrograms(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'features.png'), 'BackgroundColor', defaultBackground)) / 255;
            uitoggletool(obj.toolbar, ...
                'Tag', 'showHideFeatures', ...
                'CData', iconData, ...
                'State', states{obj.showFeatures + 1}, ...
                'TooltipString', 'Show/hide the features',... 
                'OnCallback', @(hObject, eventdata)handleToggleFeatures(obj, hObject, eventdata), ...
                'OffCallback', @(hObject, eventdata)handleToggleFeatures(obj, hObject, eventdata));
            
            drawnow;
            
            jToolbar = get(get(obj.toolbar, 'JavaContainer'), 'ComponentPeer');
            if ~isempty(jToolbar)
                jDetect = get(obj.detectPopUpTool,'JavaContainer');
                jMenu = get(jDetect,'MenuComponent');
                jMenu.removeAll;
                for actionIdx = 1:length(obj.detectorTypeNames)
                    jActionItem = jMenu.add(obj.detectorTypeNames(actionIdx));
                    oldWarn = warning('off', 'MATLAB:hg:JavaSetHGProperty');
                    oldWarn2 = warning('off', 'MATLAB:hg:PossibleDeprecatedJavaSetHGProperty');
                    set(jActionItem, 'ActionPerformedCallback', @(hObject, eventdata)handleDetectFeatures(obj, hObject, eventdata), ...
                        'UserData', actionIdx);
                    warning(oldWarn);
                    warning(oldWarn2);
                end
            end
        end
        
        
        function vp = visiblePanels(obj, isVideo)
            if isVideo
                panels = obj.videoPanels;
            else
                panels = obj.otherPanels;
            end
            
            vp = {};
            for i = 1:length(panels)
                panel = panels{i};
                if panel.visible
                    vp{end + 1} = panel; %#ok<AGROW>
                end
            end
        end
        
        
        function arrangePanels(obj)
            pos = get(obj.figure, 'Position');
            
            % Figure out which panels are currently visible.
            visibleVideoPanels = obj.visiblePanels(true);
            visibleOtherPanels = obj.visiblePanels(false);
            
            if isempty(visibleVideoPanels)
                videoPanelWidth = 0;
            else
                % Arrange the video panels
                numPanels = length(visibleVideoPanels);
                
                % TODO: toolbar icon to allow column vs. row layout?
                if true %visibleVideoPanels{1}.video.videoSize(1) < visibleVideoPanels{1}.video.videoSize(2)
                    % Arrange the videos in a column.
                    if isempty(visibleOtherPanels)
                        panelHeight = floor((pos(4) - 16) / numPanels);
                        videoPanelWidth = pos(3);
                    else
                        panelHeight = floor(pos(4) / numPanels);
                        videoPanelWidth = floor(max(cellfun(@(panel) panelHeight / panel.video.videoSize(1) * panel.video.videoSize(2), visibleVideoPanels)));
                        videoWidth = max(cellfun(@(panel) panel.video.videoSize(1), visibleVideoPanels));
                        if videoWidth < videoPanelWidth
                            videoPanelWidth = videoWidth;
                        end
                    end
                    
                    for i = 1:numPanels
                        set(visibleVideoPanels{i}.panel, 'Position', [1, pos(4) - i * panelHeight, videoPanelWidth, panelHeight]);
                    end
                else
                    % Arrange the videos in a row.
                end
            end
            
            if isempty(visibleOtherPanels)
                if ~isempty(obj.timeIndicatorPanel)
                    obj.timeIndicatorPanel.setVisible(false);
                end
            else
                % Arrange the other panels
                % Leave a one pixel gap between panels so there's a visible line between them.
                panelsHeight = pos(4) - 13 - 16;
                numPanels = length(visibleOtherPanels);
                panelHeight = floor(panelsHeight / numPanels);
                for i = 1:numPanels - 1
                    set(visibleOtherPanels{i}.panel, 'Position', [videoPanelWidth + 1, pos(4) - 13 - i * panelHeight, pos(3) - videoPanelWidth, panelHeight - 2]);
                end
                lastPanelHeight = panelsHeight - panelHeight * (numPanels - 1) - 4;
                set(visibleOtherPanels{end}.panel, 'Position', [videoPanelWidth + 1, 18, pos(3) - videoPanelWidth, lastPanelHeight]);
                
                obj.timeIndicatorPanel.setVisible(true);
                set(obj.timeIndicatorPanel.panel, 'Position', [videoPanelWidth + 1, pos(4) - 13, pos(3) - videoPanelWidth, 14]);
            end
            
            if isempty(visibleVideoPanels) || isempty(visibleOtherPanels)
                % The time slider should fill the window.
                set(obj.timeSlider, 'Position', [1, 0, pos(3), 16]);
            else
                % The time slider should only be under the non-video panels.
                set(obj.timeSlider, 'Position', [videoPanelWidth + 1, 0, pos(3) - videoPanelWidth, 16]);
            end
        end
        
        
        function handlePlayMedia(obj, ~, ~)
            set(obj.playMediaTool, 'Enable', 'off');
            set(obj.pauseMediaTool, 'Enable', 'on');
            
            if obj.selectedTime(1) ~= obj.selectedTime(2)
                % Only play within the selected range.
                if obj.currentTime >= obj.selectedTime(1) && obj.currentTime < obj.selectedTime(2) - 0.1
                    playRange = [obj.currentTime obj.selectedTime(2)];
                else
                    playRange = [obj.selectedTime(1) obj.selectedTime(2)];
                end
            else
                % Play the whole song, starting at the current time unless it's at the end.
                if obj.currentTime < obj.duration
                    playRange = [obj.currentTime obj.duration];
                else
                    playRange = [0.0 obj.duration];
                end
            end
            
            obj.isPlayingMedia = true;
            
% TODO: get audio playing again            
%             playRange = round(playRange * handles.audio.sampleRate);
%             if playRange(1) == 0
%                 playRange(1) = 1;
%             end
%             play(obj.audioPlayer, playRange);
            
            obj.mediaTimeSync = [playRange now];
            start(obj.mediaTimer);
        end
        
        
        function handleMediaTimer(obj, ~, ~)
            offset = (now - obj.mediaTimeSync(3)) * 24 * 60 * 60;
            newTime = obj.mediaTimeSync(1) + offset;
            if newTime >= obj.mediaTimeSync(2)
                obj.handlePauseMedia([], []);
            else
                obj.currentTime = newTime;
                obj.displayedTime = newTime;
            end
        end
        
        
        function handlePauseMedia(obj, hObject, ~)
            set(obj.playMediaTool, 'Enable', 'on');
            set(obj.pauseMediaTool, 'Enable', 'off');

%            stop(obj.audioPlayer);
            stop(obj.mediaTimer);
            
            obj.isPlayingMedia = false;
            
            if isempty(hObject)
                % The media played to the end without the user clicking the pause button.
                if obj.selectedTime(1) ~= obj.selectedTime(2)
                    obj.currentTime = obj.selectedTime(2);
                else
                    obj.currentTime = obj.duration;
                end
                obj.displayedTime = obj.currentTime;
            else
                obj.currentTime = obj.currentTime;
                obj.displayedTime = obj.displayedTime;
            end
        end
        
        
        function handleSaveScreenshot(obj, ~, ~)
            % TODO: determine if Ghostscript is installed and reduce choices if not.
            if isempty(obj.recordings)
                defaultPath = '';
                defaultName = 'Screenshot';
            else
                [defaultPath, defaultName, ~] = fileparts(obj.recordings(1).filePath);
            end
            [fileName, pathName] = uiputfile({'*.pdf','Portable Document Format (*.pdf)'; ...
                                              '*.png','PNG format (*.png)'; ...
                                              '*.jpg','JPEG format (*.jpg)'}, ...
                                             'Select an audio or video file to analyze', ...
                                             fullfile(defaultPath, [defaultName '.pdf']));

            if ~isnumeric(fileName)
                if ismac
                    % Make sure export_fig can find Ghostscript if it was installed via MacPorts.
                    prevEnv = getenv('DYLD_LIBRARY_PATH');
                    setenv('DYLD_LIBRARY_PATH', ['/opt/local/lib:' prevEnv]);
                end
                
                % Determine the list of axes to export.
                axesToSave = [obj.timeIndicatorPanel.axes];
                visibleVideoPanels = obj.visiblePanels(true);
                for i = 1:length(visibleVideoPanels)
                    axesToSave(end + 1) = visibleVideoPanels{i}.axes; %#ok<AGROW>
                end
                visibleOtherPanels = obj.visiblePanels(false);
                for i = 1:length(visibleOtherPanels)
                    axesToSave(end + 1) = visibleOtherPanels{i}.axes; %#ok<AGROW>
%                    visibleOtherPanels{i}.showSelection(false);
                end
                
                print(obj.figure, '-dpng', fullfile(pathName, fileName));
%                export_fig(fullfile(pathName, fileName), '-opengl', '-a1');  %, axesToSave);

                % Show the current selection again.
                for i = 1:length(visibleOtherPanels)
                    visibleOtherPanels{i}.showSelection(true);
                end
                
                if ismac
                    setenv('DYLD_LIBRARY_PATH', prevEnv);
                end
            end
        end
        
        
        function handleToggleWaveforms(obj, ~, ~)
            obj.showWaveforms = ~obj.showWaveforms;
            for i = 1:length(obj.otherPanels)
                panel = obj.otherPanels{i};
                if isa(panel, 'WaveformPanel')
                    panel.setVisible(obj.showWaveforms);
                end
            end
            
            obj.arrangePanels();
            
            setpref('SongAnalysis', 'ShowWaveforms', obj.showWaveforms);
        end
        
        
        function handleToggleSpectrograms(obj, ~, ~)
            obj.showSpectrograms = ~obj.showSpectrograms;
            for i = 1:length(obj.otherPanels)
                panel = obj.otherPanels{i};
                if isa(panel, 'SpectrogramPanel')
                    panel.setVisible(obj.showSpectrograms);
                end
            end
            
            obj.arrangePanels();
            
            setpref('SongAnalysis', 'ShowSpectrograms', obj.showSpectrograms);
        end
        
        
        function handleToggleFeatures(obj, ~, ~)
            obj.showFeatures = ~obj.showFeatures;
            for i = 1:length(obj.otherPanels)
                panel = obj.otherPanels{i};
                if isa(panel, 'FeaturesPanel')
                    panel.setVisible(obj.showFeatures);
                end
            end
            
            obj.arrangePanels();
            
            setpref('SongAnalysis', 'ShowFeatures', obj.showFeatures);
        end
        
        
        function handleDetectFeatures(obj, hObject, ~)
            index = get(hObject, 'UserData');
            
            if isempty(index)
                % The user clicked the icon instead of the little pop-up arrow.
                % We want the pop-up menu to appear in this case as well.
                jDetect = get(obj.detectPopUpTool,'JavaContainer');
                if ~isempty(jDetect)
                    jDetect.showMenu();
                else
                    waitfor(warndlg({'Could not automatically pop up the detectors toolbar menu.', '', 'Please click the small arrow next to the icon instead.'}, 'Song Analysis', 'modal'));
                end
            else
                detectorClassName = obj.detectorClassNames{index};
                
                constructor = str2func(detectorClassName);
                detector = constructor(obj);

                if detector.editSettings()
%TODO               addContextualMenu(detector);

                    detector.startProgress();
                    try
                        if obj.selectedTime(2) > obj.selectedTime(1)
                            n = detector.detectFeatures(obj.selectedTime);
                        else
                            n = detector.detectFeatures([0.0 obj.duration]);
                        end
                        detector.endProgress();

                        if n == 0
                            waitfor(msgbox('No features were detected.', detectorClassName, 'warn', 'modal'));
                        else
                            obj.reporters{end + 1} = detector;
                            obj.otherPanels{end + 1} = FeaturesPanel(detector);

                            obj.arrangePanels();

                        end

%TODO                   handles = updateFeatureTimes(handles);
                    catch ME
                        waitfor(msgbox(['An error occurred while detecting features:' char(10) char(10) ME.message char(10) char(10) '(See the command window for details.)'], ...
                                       detectorClassName, 'error', 'modal'));
                        detector.endProgress();
                        rethrow(ME);
                    end
                end
            end
        end
        
        
        function removeFeaturePanel(obj, featurePanel)
            answer = questdlg('Are you sure you wish to remove this reporter?', 'Removing Reporter', 'Cancel', 'Remove', 'Cancel');
            if strcmp(answer, 'Remove')
                obj.otherPanels(cellfun(@(x) x == featurePanel, obj.otherPanels)) = [];
                delete(featurePanel);
                obj.arrangePanels();
                
% TODO:                handles = updateFeatureTimes(handles);
            end
        end
        
        
        function setZoom(obj, zoom)
            if zoom < 1
                obj.zoom = 1;
            else
                obj.zoom = zoom;
            end
            
            obj.timeWindow = obj.duration / obj.zoom;
            
            obj.displayedTime = sum(obj.selectedTime) / 2;
            
            if obj.zoom > 1
                set(obj.zoomOutTool, 'Enable', 'on')
            else
                set(obj.zoomOutTool, 'Enable', 'off')
            end
        end
        
        
        function handleZoomIn(obj, ~, ~)
            obj.setZoom(obj.zoom * 2);
        end
        
        
        function handleZoomOut(obj, ~, ~)
            obj.setZoom(obj.zoom / 2);
        end
        
        
        function handleResize(obj, ~, ~)
            obj.arrangePanels();
        end
        
        
        function handleMouseButtonDown(obj, ~, ~)
            if strcmp(get(gcf, 'SelectionType'), 'alt')
                return  % Don't change the curren time or selection when control/right clicking.
            end
            
            clickedObject = get(obj.figure, 'CurrentObject');
            
            % TODO: allow panels to handle clicks on their objects
            %
            %     handled = panel{i}.handleMouseDown(...);
            %     if ~handled
            %         ...
            
            for i = 1:length(obj.otherPanels)
                if clickedObject == obj.otherPanels{i}.axes
                    clickedPoint = get(clickedObject, 'CurrentPoint');
                    clickedTime = clickedPoint(1);
                    if strcmp(get(gcf, 'SelectionType'), 'extend')
                        if obj.currentTime == obj.selectedTime(1) || obj.currentTime ~= obj.selectedTime(2)
                            obj.selectedTime = sort([obj.selectedTime(1) clickedTime]);
                        else
                            obj.selectedTime = sort([clickedTime obj.selectedTime(2)]);
                        end
                    else
                        obj.currentTime = clickedTime;
                        obj.selectedTime = [clickedTime clickedTime];
                        obj.panelSelectingTime = obj.otherPanels{i};
                    end
                    
                    break
                end
            end
        end


        function handleMouseMotion(obj, ~, ~)
            if ~isempty(obj.panelSelectingTime)
                clickedPoint = get(obj.panelSelectingTime.axes, 'CurrentPoint');
                clickedTime = clickedPoint(1);
                if obj.currentTime == obj.selectedTime(1) || obj.currentTime ~= obj.selectedTime(2)
                    obj.selectedTime = sort([obj.selectedTime(1) clickedTime]);
                else
                    obj.selectedTime = sort([clickedTime obj.selectedTime(2)]);
                end
            elseif false    %handles.showSpectrogram && isfield(handles, 'spectrogramTooltip')
% TODO:
%                 currentPoint = get(handles.spectrogram, 'CurrentPoint');
%                 xLim = get(handles.spectrogram, 'XLim');
%                 yLim = get(handles.spectrogram, 'YLim');
%                 x = (currentPoint(1, 1) - xLim(1)) / (xLim(2) - xLim(1));
%                 y = (currentPoint(1, 2) - yLim(1)) / (yLim(2) - yLim(1));
%                 if x >=0 && x <= 1 && y >= 0 && y <= 1
%                     timeRange = displayedTimeRange(handles);
%                     currentTime = timeRange(1) + (timeRange(2) - timeRange(1)) * x;
%                     frequency = handles.spectrogramFreqMin + ...
%                         (handles.spectrogramFreqMax - handles.spectrogramFreqMin) * y;
%                     tip = sprintf('%0.2f sec\n%.1f Hz', currentTime, frequency);
%                     set(handles.spectrogramTooltip, 'String', tip, 'Visible', 'on');
%                 else
%                     tip = '';
%                     set(handles.spectrogramTooltip, 'String', tip, 'Visible', 'off');
%                 end
            end
        end


        function handleMouseButtonUp(obj, ~, ~)
            if ~isempty(obj.panelSelectingTime)
                clickedPoint = get(obj.panelSelectingTime.axes, 'CurrentPoint');
                clickedTime = clickedPoint(1);
                if obj.currentTime == obj.selectedTime(1) || obj.currentTime ~= obj.selectedTime(2)
                    obj.selectedTime = sort([obj.selectedTime(1) clickedTime]);
                else
                    obj.selectedTime = sort([clickedTime obj.selectedTime(2)]);
                end
                obj.panelSelectingTime = [];
            end
        end
        
        
        function handleKeyPress(obj, ~, keyEvent)
            if ~strcmp(keyEvent.Key, 'space')
                % Let one of the panels handle the event.
                visiblePanels = horzcat(obj.visiblePanels(false), obj.visiblePanels(true));
                for i = 1:length(visiblePanels)
                    if visiblePanels{i}.keyWasPressed(keyEvent)
                        break
                    end
                end
            end
        end
        
        
        function handleKeyRelease(obj, source, keyEvent)
            if strcmp(keyEvent.Key, 'space')
                if obj.isPlayingMedia
                    obj.handlePauseMedia(source, keyEvent);
                else
                    obj.handlePlayMedia(source, keyEvent);
                end
            else
                % Let one of the panels handle the event.
                visiblePanels = horzcat(obj.visiblePanels(false), obj.visiblePanels(true));
                for i = 1:length(visiblePanels)
                    if visiblePanels{i}.keyWasReleased(keyEvent)
                        break
                    end
                end
            end
        end
        
        
        function handleTimeSliderChanged(obj, ~, ~)
            if get(obj.timeSlider, 'Value') ~= obj.displayedTime
                obj.displayedTime = get(obj.timeSlider, 'Value');
            end
        end
        
        
        function handleTimeWindowChanged(obj, ~, ~)
            set(obj.timeSlider, 'Value', obj.displayedTime);
            
            % Adjust the step and page sizes of the time slider.
            stepSize = 1 / obj.zoom;
            set(obj.timeSlider, 'SliderStep', [stepSize / 50.0 stepSize]);
        end
        
        
        function handleOpenFile(obj, ~, ~)
            [fileNames, pathName] = uigetfile2('Select an audio or video file to analyze');
            
            if ischar(fileNames)
                fileNames = {fileNames};
            elseif isnumeric(fileNames)
                fileNames = {};
            end
            
            somethingOpened = false;

            for i = 1:length(fileNames)
                fileName = fileNames{i};
                fullPath = fullfile(pathName, fileName);

                % Handle special characters in the file name.
                NFD = javaMethod('valueOf', 'java.text.Normalizer$Form','NFD');
                UTF8=java.nio.charset.Charset.forName('UTF-8');
                s = java.lang.String(fullPath);
                sc = java.text.Normalizer.normalize(s,NFD);
                bs = single(sc.getBytes(UTF8)');
                bs(bs < 0) = 256 + (bs(bs < 0));
                fullPath = char(bs);

                % First check if the file can be imported by one of the feature importers.
                try
                    possibleImporters = [];
                    for j = 1:length(obj.importerClassNames)
                        if eval([obj.importerClassNames{j} '.canImportFromPath(''' strrep(fullPath, '''', '''''') ''')'])
                            possibleImporters(end+1) = j; %#ok<AGROW>
                        end
                    end
                    
                    if ~isempty(possibleImporters)
                        index = [];
                        if length(possibleImporters) == 1
                            index = possibleImporters(1);
                        else
                            choice = listdlg('PromptString', 'Choose which importer to use:', ...
                                             'SelectionMode', 'Single', ...
                                             'ListString', handles.importerTypeNames(possibleImporters));
                            if ~isempty(choice)
                                index = choice(1);
                            end
                        end
                        if ~isempty(index)
                            obj.importing = true;
                            constructor = str2func(obj.importerClassNames{index});
                            importer = constructor(obj, fullPath);
                            importer.startProgress();
                            try
                                n = importer.importFeatures();
                                importer.endProgress();
                                obj.importing = false;
                                
                                for rec = obj.recordingsToAdd
                                    if rec.isAudio
                                        obj.addAudioRecording(rec);
                                    elseif rec.isVideo
                                        obj.addVideoRecording(rec);
                                    end
                                end
                                obj.recordingsToAdd = Recording.empty();
                                
                                if n == 0
                                    waitfor(msgbox('No features were imported.', obj.importerTypeNames{index}, 'warn', 'modal'));
                                else
                                    obj.reporters{end + 1} = importer;
                                    obj.otherPanels{end + 1} = FeaturesPanel(importer);
                                    
                                    obj.arrangePanels();
                                    
                                    somethingOpened = true;
                                end
                            catch ME
                                importer.endProgress();
                                obj.importing = false;
                                obj.recordingsToAdd = Recording.empty();
                                waitfor(msgbox('An error occurred while importing features.  (See the command window for details.)', obj.importerTypeNames{index}, 'error', 'modal'));
                                rethrow(ME);
                            end

% TODO                            addContextualMenu(importer);
                        end
                    end
                catch ME
                    rethrow(ME);
                end

                % Next check if it's an audio or video file.
                try
                    set(obj.figure, 'Pointer', 'watch'); drawnow
                    recs = Recording(fullPath,obj.recordings);
                    
                    for j = 1:length(recs)
                        rec = recs(j);
                        if rec.isAudio
                            obj.addAudioRecording(rec);
                            somethingOpened = true;
                        elseif rec.isVideo
                            obj.addVideoRecording(rec);
                            somethingOpened = true;
                        end
                    end
                    set(obj.figure, 'Pointer', 'arrow'); drawnow
                catch ME
                    set(obj.figure, 'Pointer', 'arrow'); drawnow
                    warndlg(sprintf('Error opening media file:\n\n%s', ME.message));
                    rethrow(ME);
                end
            end
            
            if somethingOpened
                obj.duration = max([obj.recordings.duration cellfun(@(r) r.duration, obj.reporters)]);
                
                % Alter the zoom so that the same window of time is visible.
                if obj.timeWindow == 0
                    obj.timeWindow = obj.duration;
                    obj.setZoom(1);
                else
                    obj.setZoom(obj.duration / obj.timeWindow);
                end
                
                set(obj.timeSlider, 'Max', obj.duration);
                
                obj.displayedTime = obj.displayedTime;
            end
        end
        
        
        function addAudioRecording(obj, recording)
            if obj.importing
                % There seems to be a bug in MATLAB where you can't create new axes while a waitbar is open.
                % Queue the recording to be added after the waitbar has gone away.
                obj.recordingsToAdd(end + 1) = recording;
            else
                if isempty(obj.recordings)
                    set(obj.figure, 'Name', ['Song Analysis: ' recording.name]);
                end
                
                obj.recordings(end + 1) = recording;
                
                panel = WaveformPanel(obj, recording);
                obj.otherPanels{end + 1} = panel;
                panel.setVisible(obj.showWaveforms);
                
                panel = SpectrogramPanel(obj, recording);
                obj.otherPanels{end + 1} = panel;
                panel.setVisible(obj.showSpectrograms);
                
                obj.arrangePanels();
            end
        end
        
        
        function addVideoRecording(obj, recording)
            if obj.importing
                % There seems to be a bug in MATLAB where you can't create new axes while a waitbar is open.
                % Queue the recording to be added after the waitbar has gone away.
                obj.recordingsToAdd(end + 1) = recording;
            else
                if isempty(obj.recordings)
                    set(obj.figure, 'Name', ['Song Analysis: ' recording.name]);
                end
                
                obj.recordings(end + 1) = recording;
                
                panel = VideoPanel(obj, recording);
                obj.videoPanels{end + 1} = panel;
                
                obj.arrangePanels();
            end
        end
        
        
        function range = displayedTimeRange(obj)
            timeRangeSize = obj.duration / obj.zoom;
            range = [obj.displayedTime - timeRangeSize / 2 obj.displayedTime + timeRangeSize / 2];
            if range(2) - range(1) > obj.duration
                range = [0.0 obj.duration];
            elseif range(1) < 0.0
                range = [0.0 timeRangeSize];
            elseif range(2) > obj.duration
                range = [obj.duration - timeRangeSize obj.duration];
            end
        end
        
        
        function handleSaveAllFeatures(obj, ~, ~)
            % Save the features from all of the reporters.
            if length(obj.recordings) == 1
                obj.saveFeatures(obj.reporters, obj.recordings(1).name);
            else
                obj.saveFeatures(obj.reporters);
            end
        end
        
        
        function saveFeatures(obj, reporters, fileName)
            if nargin < 4
                fileName = 'Song';
            end
            
            [fileName, pathName, filterIndex] = uiputfile({'*.mat', 'MATLAB file';'*.txt', 'Text file'}, 'Save features as', [fileName ' features.mat']);
            
            if ischar(fileName)
                features = {};
                for i = 1:length(reporters)
                    features = horzcat(features, reporters{i}.features()); %#ok<AGROW>
                end

                if filterIndex == 1
                    % Save as a MATLAB file
                    featureTypes = {features.type}; %#ok<NASGU>
                    startTimes = arrayfun(@(a) a.startTime, features); %#ok<NASGU>
                    stopTimes = arrayfun(@(a) a.endTime, features); %#ok<NASGU>

                    % TODO: also save audio recording path, reporter properties, ???
                    save(fullfile(pathName, fileName), 'features', 'featureTypes', 'startTimes', 'stopTimes');
                else
                    % Save as an Excel tsv file
                    fid = fopen(fullfile(pathName, fileName), 'w');

                    propNames = {};
                    ignoreProps = {'type', 'sampleRange', 'contextualMenu', 'startTime', 'endTime'};

                    % Find all of the feature properties so we know how many columns there will be.
                    for f = 1:length(features)
                        feature = features(f);
                        props = properties(feature);
                        for p = 1:length(props)
                            if ~ismember(props{p}, ignoreProps)
                                propName = [feature.type ':' props{p}];
                                if ~ismember(propName, propNames)
                                    propNames{end + 1} = propName; %#ok<AGROW>
                                end
                            end
                        end
                    end
                    propNames = sort(propNames);

                    % Save a header row.
                    fprintf(fid, 'Type\tStart Time\tEnd Time');
                    for p = 1:length(propNames)
                        fprintf(fid, '\t%s', propNames{p});
                    end
                    fprintf(fid, '\n');

                    for i = 1:length(features)
                        feature = features(i);
                        fprintf(fid, '%s\t%f\t%f', feature.type, feature.startTime, feature.endTime);

                        propValues = cell(1, length(propNames));
                        props = sort(properties(feature));
                        for j = 1:length(props)
                            if ~ismember(props{j}, ignoreProps)
                                propName = [feature.type ':' props{j}];
                                index = strcmp(propNames, propName);
                                value = feature.(props{j});
                                if isnumeric(value)
                                    value = num2str(value);
                                end
                                propValues{index} = value;
                            end
                        end
                        for p = 1:length(propNames)
                            fprintf(fid, '\t%s', propValues{p});
                        end
                        fprintf(fid, '\n');
                    end

                    fclose(fid);
                end
            end
        end
        
        
        function handleClose(obj, ~, ~)
            if obj.isPlayingMedia
                stop(obj.mediaTimer);
            end
            delete(obj.mediaTimer);

            % Remember the window position.
            setpref('SongAnalysis', 'MainWindowPosition', get(obj.figure, 'Position'));

% TODO:
%             if (handles.close_matlabpool)
%               matlabpool close
%             end
            
            % TODO: Send a "will close" message to all of the panels?
            
            % Fix a Java memory leak that prevents this object from ever being deleted.
            % TODO: there's probably a better way to do this...
            jDetect = get(obj.detectPopUpTool, 'JavaContainer');
            jMenu = get(jDetect, 'MenuComponent');
            if ~isempty(jMenu)
                jMenuItems = jMenu.getSubElements();
                for i = 1:length(jMenuItems)
                    oldWarn = warning('off', 'MATLAB:hg:JavaSetHGProperty');
                    oldWarn2 = warning('off', 'MATLAB:hg:PossibleDeprecatedJavaSetHGProperty');
                    set(jMenuItems(i), 'ActionPerformedCallback', []);
                    warning(oldWarn);
                    warning(oldWarn2);
                end
            end
            
            delete(obj.figure);
        end
        
    end
    
end


function [classNames, typeNames] = findPlugIns(pluginsDir)
    pluginDirs = dir(pluginsDir);
    classNames = cell(length(pluginDirs), 1);
    typeNames = cell(length(pluginDirs), 1);
    pluginCount = 0;
    for i = 1:length(pluginDirs)
        if pluginDirs(i).isdir && pluginDirs(i).name(1) ~= '.'
            className = pluginDirs(i).name;
            try
                addpath(fullfile(pluginsDir, filesep, className));
                eval([className '.initialize()'])
                pluginCount = pluginCount + 1;
                classNames{pluginCount} = className;
                typeNames{pluginCount} = eval([className '.typeName()']);
            catch ME
                waitfor(warndlg(['Could not load ' pluginDirs(i).name ': ' ME.message]));
                rmpath(fullfile(pluginsDir, filesep, pluginDirs(i).name));
            end
        end
    end
    classNames = classNames(1:pluginCount);
    typeNames = typeNames(1:pluginCount);
end
