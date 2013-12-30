classdef TempoController < handle
    
    properties
        figure
        
        recordings = {}
        reporters = {}
        
        duration = 300
        zoom = 1
        
        splitterPanel
        splitter
        videosPanel
        videoPanels = {}
        timelinesPanel
        timelinePanels = {}
        timeIndicatorPanel = []
        
        timeSlider
        
        toolbar
        zoomOutTool
        playMediaTool
        pauseMediaTool
        detectPopUpTool
        showWaveformsTool
        showSpectrogramsTool
        showFeaturesTool
        toolStates = {'off', 'on'}
        
        timeLabelFormat = 1     % default to displaying time in minutes and seconds
        
        panelSelectingTime
        mouseConstraintTime
        mouseConstraintFreq
        originalSelectedRange
        mouseOffset
        
        isPlayingMedia = false
        playTimer
        mediaTimer
        mediaTimeSync
        
        recordingClassNames
        recordingTypeNames
        detectorClassNames
        detectorTypeNames
        importerClassNames
        importerTypeNames
        
        importing = false
        recordingsToAdd = {}
        
        showWaveforms
        showSpectrograms
        showFeatures
        
        needsSave = false
        savePath
        
        frameCount
    end
    
    
    properties (SetObservable)
        % The Tempo panels will listen for changes to these properties.
        displayRange = []      % The window in time and frequency which all non-video panels should display (in seconds/Hz, [minTime maxTime minFreq maxFreq]).
        currentTime = 0         % The time point currently being played (in seconds).
        selectedRange = [0 0 -inf inf]    % The range of time and frequency currently selected (in seconds/Hz).  The first two values will be equal if there is a point selection.
        windowSize = 0
    end
    
    
    methods
        
        function obj = TempoController()
            obj.showWaveforms = getpref('Tempo', 'ShowWaveforms', true);
            obj.showSpectrograms = getpref('Tempo', 'ShowSpectrograms', true);
            obj.showFeatures = getpref('Tempo', 'ShowFeatures', true);
            
            obj.figure = figure('Name', 'Tempo', ...
                'NumberTitle', 'off', ...
                'Toolbar', 'none', ...
                'MenuBar', 'none', ...
                'Position', getpref('Tempo', 'MainWindowPosition', [100 100 400 200]), ...
                'Color', [0.4 0.4 0.4], ...
                'Renderer', 'opengl', ...
                'ResizeFcn', @(source, event)handleResize(obj, source, event), ...
                'KeyPressFcn', @(source, event)handleKeyPress(obj, source, event), ...
                'KeyReleaseFcn', @(source, event)handleKeyRelease(obj, source, event), ...
                'CloseRequestFcn', @(source, event)handleClose(obj, source, event), ...
                'WindowButtonDownFcn', @(source, event)handleMouseButtonDown(obj, source, event), ...
                'WindowButtonUpFcn', @(source, event)handleMouseButtonUp(obj, source, event)); %#ok<CPROP>
            
            if isdeployed && exist(fullfile(ctfroot, 'Detectors'), 'dir')
                % Look for the detectors in the CTF archive.
                parentDir = ctfroot;
            else
                % Look for the detectors relative to this .m file.
                tempoPath = mfilename('fullpath');
                parentDir = fileparts(tempoPath);
            end
            
            addpath(fullfile(parentDir, 'TempoPanels'));
            addpath(fullfile(parentDir, 'Recordings'));
            addpath(fullfile(parentDir, 'Utility'));
            
            [obj.recordingClassNames, obj.recordingTypeNames] = findPlugIns(fullfile(parentDir, 'Recordings'));
            [obj.detectorClassNames, obj.detectorTypeNames] = findPlugIns(fullfile(parentDir, 'Detectors'));
            [obj.importerClassNames, obj.importerTypeNames] = findPlugIns(fullfile(parentDir, 'Importers'));
            
            % Add the paths to the third-party code.
            addpath(fullfile(parentDir, 'ThirdParty', 'export_fig'));
            addpath(fullfile(parentDir, 'ThirdParty', 'dbutils'));
            addpath(fullfile(parentDir, 'ThirdParty', 'ffmpeg'));
            addpath(fullfile(parentDir, 'ThirdParty', 'uisplitpane'));
            
            % Insert a splitter at the top level to separate the video and timeline panels.
            % TODO: Allow the splitter to split the screen vertically with the video panels on top.
            %       This will require removing and re-adding the uisplitpane since that property cannot be modified.
            set(obj.figure, 'WindowButtonMotionFcn', @()handleMouseMotion(obj));
            figurePos = get(obj.figure, 'Position');
            obj.splitterPanel = uipanel(obj.figure, ...
                'BorderType', 'none', ...
                'BorderWidth', 0, ...
                'BackgroundColor', [0.25 0.25 0.25], ...
                'SelectionHighlight', 'off', ...
                'Units', 'pixels', ...
                'Position', [0 16 figurePos(3) figurePos(4) - 16]);
            [obj.videosPanel, obj.timelinesPanel, obj.splitter] = uisplitpane(obj.splitterPanel, ...
                'DividerLocation', 0.25, ...
                'DividerColor', 'red', ...
                'DividerWidth', 5);
            set(obj.videosPanel, ...
                'BackgroundColor', 'black', ...
                'ResizeFcn', @(source, event)arrangeVideoPanels(obj, source, event));
            set(obj.timelinesPanel, ...
                'BackgroundColor', 'white', ...
                'ResizeFcn', @(source, event)arrangeTimelinePanels(obj, source, event));
            set(obj.splitter, 'DividerColor', 'red');
            
            obj.timeIndicatorPanel = TimeIndicatorPanel(obj);
            
            obj.createMenuBar();
            obj.createToolbar();
            
            % Create the scroll bar that lets the user scrub through time.
            obj.timeSlider = uicontrol(...
                'Parent', obj.figure, ...
                'Style', 'slider',... 
                'Min', 0, ...
                'Max', obj.duration, ...
                'Value', 0, ...
                'Position', [1 1 figurePos(3) 16]);
            if verLessThan('matlab', '7.12.0')
                addlistener(obj.timeSlider, 'Action', @(source, event)handleTimeSliderChanged(obj, source, event));
            else
                addlistener(obj.timeSlider, 'ContinuousValueChange', @(source, event)handleTimeSliderChanged(obj, source, event));
            end
            
            % Listen for changes to the displayRange property.
            addlistener(obj, 'displayRange', 'PostSet', @(source, event)handleTimeWindowChanged(obj, source, event));
            
            obj.arrangeTimelinePanels();
            
            % Set up a timer to fire 30 times per second when the media is being played.
            obj.mediaTimer = timer('ExecutionMode', 'fixedRate', 'TimerFcn', @(timerObj, event)handleMediaTimer(obj, timerObj, event), 'Period', round(1.0 / 30.0 * 1000) / 1000);
        end
        
        
        function createMenuBar(obj)
            fileMenu = uimenu(obj.figure, 'Label', 'File');
            uimenu(fileMenu, 'Label', 'New', ...
                             'Callback', @(hObject, eventdata)handleNewWorkspace(obj, hObject, eventdata), ...
                             'Accelerator', 'n');
            uimenu(fileMenu, 'Label', 'Open...', ...
                             'Callback', @(hObject, eventdata)handleOpenFile(obj, hObject, eventdata), ...
                             'Accelerator', 'o');
            uimenu(fileMenu, 'Label', 'Close', ...
                             'Callback', @(hObject, eventdata)handleClose(obj, hObject, eventdata), ...
                             'Accelerator', 'w', ...
                             'Separator', 'on');
            uimenu(fileMenu, 'Label', 'Close All', ...
                             'Callback', '', ...
                             'Enable', 'off');
            uimenu(fileMenu, 'Label', 'Save...', ...
                             'Callback', @(hObject, eventdata)handleSaveWorkspace(obj, hObject, eventdata), ... 
                             'Accelerator', 's');
             uimenu(fileMenu, 'Label', 'Save As...', ...
                             'Callback', '', ... 
                             'Accelerator', '', ...
                             'Enable', 'off');
           uimenu(fileMenu, 'Label', 'Export Video of Selection...', ...
                             'Callback', @(hObject, eventdata)handleExportSelection(obj, hObject, eventdata), ...
                             'Separator', 'on');
            uimenu(fileMenu, 'Label', 'Export All Features...', ...
                             'Callback', '', ...
                             'Enable', 'off');
            uimenu(fileMenu, 'Label', 'Take Screen Shot...', ...
                             'Callback', @(hObject, eventdata)handleSaveScreenshot(obj, hObject, eventdata), ... 
                             'Separator', 'on');
            
            editMenu = uimenu(obj.figure, 'Label', 'Edit');
            uimenu(editMenu, 'Label', 'Undo', ...
                             'Callback', '', ...
                             'Accelerator', 'z', ...
                             'Enable', 'off');
            uimenu(editMenu, 'Label', 'Redo...', ...
                             'Callback', '', ...
                             'Accelerator', 'Z', ...
                             'Enable', 'off');
            uimenu(editMenu, 'Label', 'Cut', ...
                             'Callback', '', ...
                             'Accelerator', 'x', ...
                             'Separator', 'on', ...
                             'Enable', 'off');
            uimenu(editMenu, 'Label', 'Copy', ...
                             'Callback', '', ...
                             'Accelerator', 'c', ...
                             'Enable', 'off');
            uimenu(editMenu, 'Label', 'Paste', ...
                             'Callback', '', ... 
                             'Accelerator', 'v', ...
                             'Enable', 'off');
            uimenu(editMenu, 'Label', 'Select All', ...
                             'Callback', @(hObject, eventdata)handleSelectAll(obj, hObject, eventdata), ...
                             'Accelerator', 'a', ...
                             'Separator', 'on');
            uimenu(editMenu, 'Label', 'Select None', ...
                             'Callback', @(hObject, eventdata)handleSelectNone(obj, hObject, eventdata), ...
                             'Accelerator', '');
            detectorMenu = uimenu(editMenu, 'Label', 'Detect Features', ...
                                            'Callback', '', ... 
                                            'Separator', 'on');
            for detectorIdx = 1:length(obj.detectorTypeNames)
                uimenu(detectorMenu, 'Label', obj.detectorTypeNames{detectorIdx}, ...
                                     'Callback', @(hObject, eventdata)handleDetectFeatures(obj, hObject, eventdata), ...
                                     'UserData', detectorIdx);
            end
            
            videoMenu = uimenu(obj.figure, 'Label', 'Video');
            uimenu(videoMenu, 'Label', 'View at Actual Size', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'View at Double Size', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'View at Half Size', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'View at Maximum Size', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Checked', 'on', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'Arrange Videos Left to Right', ...
                              'Callback', '', ...
                              'Accelerator', '', ... 
                              'Separator', 'on', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'Arrange Videos Top to Bottom', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Checked', 'on', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'Place Videos Left of the Timeline', ...
                              'Callback', '', ...
                              'Accelerator', '', ... 
                              'Separator', 'on', ...
                              'Checked', 'on', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'Place Videos Above the Timeline', ...
                              'Callback', '', ...
                              'Accelerator', '', ...
                              'Enable', 'off');
            uimenu(videoMenu, 'Label', 'Show Current Frame Number', ...
                              'Callback', '', ...
                              'Accelerator', '', ... 
                              'Separator', 'on', ...
                              'Checked', 'on', ...
                              'Enable', 'off');
            
            
            timelineMenu = uimenu(obj.figure, 'Label', 'Timeline');
            uimenu(timelineMenu, 'Label', 'Zoom In', ...
                                 'Callback', @(hObject, eventdata)handleZoomIn(obj, hObject, eventdata), ...
                                 'Accelerator', '');
            uimenu(timelineMenu, 'Label', 'Zoom Out', ...
                                 'Callback', @(hObject, eventdata)handleZoomOut(obj, hObject, eventdata), ...
                                 'Accelerator', '');
            uimenu(timelineMenu, 'Label', 'Zoom to Selection', ...
                                 'Callback', @(hObject, eventdata)handleZoomToSelection(obj, hObject, eventdata), ...
                                 'Accelerator', '');
            uimenu(timelineMenu, 'Label', 'Open Waveform for New Recordings', ...
                                 'Callback', '', ...
                                 'Separator', 'on', ...
                                 'Checked', 'on', ...
                                 'Enable', 'off');
            uimenu(timelineMenu, 'Label', 'Open Spectrogram for New Recordings', ...
                                 'Callback', '', ...
                                 'Checked', 'on', ...
                                 'Enable', 'off');
            
            playbackMenu = uimenu(obj.figure, 'Label', 'Playback');
            uimenu(playbackMenu, 'Label', 'Play', ...
                                 'Callback', @(hObject, eventdata)handlePlayMedia(obj, hObject, eventdata), ...
                                 'Accelerator', '');
            uimenu(playbackMenu, 'Label', 'Pause', ...
                                 'Callback', @(hObject, eventdata)handlePauseMedia(obj, hObject, eventdata), ...
                                 'Accelerator', '');
            uimenu(playbackMenu, 'Label', 'Play at Regular Speed', ...
                                 'Callback', '', ...
                                 'Accelerator', '1', ...
                                 'Separator', 'on', ...
                                 'Checked', 'on', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Play at Double Speed', ...
                                 'Callback', '', ...
                                 'Accelerator', '2', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Play at Half Speed', ...
                                 'Callback', '', ...
                                 'Accelerator', '', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Increase Speed', ...
                                 'Callback', '', ...
                                 'Accelerator', '', ...
                                 'Separator', 'on', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Decrease Speed', ...
                                 'Callback', '', ...
                                 'Accelerator', '', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Play Forwards', ...
                                 'Callback', '', ...
                                 'Accelerator', '', ...
                                 'Separator', 'on', ...
                                 'Checked', 'on', ...
                                 'Enable', 'off');
            uimenu(playbackMenu, 'Label', 'Play Backwards', ...
                                 'Callback', '', ...
                                 'Accelerator', '', ...
                                 'Enable', 'off');
        end
        
        
        function createToolbar(obj)
            % Open | Zoom in Zoom out | Play Pause | Find features | Save features Save screenshot | Show/hide waveforms Show/hide features Toggle time format
            obj.toolbar = uitoolbar(obj.figure);
            
            [tempoRoot, ~, ~] = fileparts(mfilename('fullpath'));
            iconRoot = fullfile(tempoRoot, 'Icons');
            defaultBackground = get(0, 'defaultUicontrolBackgroundColor');
            
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'file_open.png'), 'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'openFile', ...
                'CData', iconData, ...
                'TooltipString', 'Open a saved workspace, open audio/video files or import features',... 
                'Separator', 'on', ...
                'ClickedCallback', @(hObject, eventdata)handleOpenFile(obj, hObject, eventdata));
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'file_save.png'),'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'saveWorkspace', ...
                'CData', iconData, ...
                'TooltipString', 'Save the workspace',...
                'ClickedCallback', @(hObject, eventdata)handleSaveWorkspace(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(matlabroot, 'toolbox', 'matlab', 'icons', 'tool_shape_rectangle.png'),'BackgroundColor', defaultBackground)) / 65535;
            uipushtool(obj.toolbar, ...
                'Tag', 'exportSelection', ...
                'CData', iconData, ...
                'TooltipString', 'Export the selected time window to a movie',...
                'ClickedCallback', @(hObject, eventdata)handleExportSelection(obj, hObject, eventdata));
            
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
            
            iconData = double(imread(fullfile(iconRoot, 'screenshot.png'), 'BackgroundColor', defaultBackground)) / 255;
            uipushtool(obj.toolbar, ...
                'Tag', 'saveScreenshot', ...
                'CData', iconData, ...
                'TooltipString', 'Save a screenshot',...
                'ClickedCallback', @(hObject, eventdata)handleSaveScreenshot(obj, hObject, eventdata));
            
            iconData = double(imread(fullfile(iconRoot, 'waveform.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.showWaveformsTool = uitoggletool(obj.toolbar, ...
                'Tag', 'showHideWaveforms', ...
                'CData', iconData, ...
                'State', obj.toolStates{obj.showWaveforms + 1}, ...
                'TooltipString', 'Show/hide the waveform(s)',... 
                'Separator', 'on', ...
                'OnCallback', @(hObject, eventdata)handleToggleWaveforms(obj, hObject, eventdata), ...
                'OffCallback', @(hObject, eventdata)handleToggleWaveforms(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'spectrogram.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.showSpectrogramsTool = uitoggletool(obj.toolbar, ...
                'Tag', 'showHideSpectrograms', ...
                'CData', iconData, ...
                'State', obj.toolStates{obj.showSpectrograms + 1}, ...
                'TooltipString', 'Show/hide the spectrogram(s)',... 
                'OnCallback', @(hObject, eventdata)handleToggleSpectrograms(obj, hObject, eventdata), ...
                'OffCallback', @(hObject, eventdata)handleToggleSpectrograms(obj, hObject, eventdata));
            iconData = double(imread(fullfile(iconRoot, 'features.png'), 'BackgroundColor', defaultBackground)) / 255;
            obj.showFeaturesTool = uitoggletool(obj.toolbar, ...
                'Tag', 'showHideFeatures', ...
                'CData', iconData, ...
                'State', obj.toolStates{obj.showFeatures + 1}, ...
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
        
        
        function panels = panelsOfClass(obj, panelClass)
            % Return a cell array of panel instances of the given class.
            % A cell array is needed in case a base panel class is specified, e.g. TimelinePanel.
            
            panels = {};
            for i = 1:length(obj.videoPanels)
                panel = obj.videoPanels{i};
                if isa(panel, panelClass)
                    panels{end + 1} = panel; %#ok<AGROW>
                end
            end
            for i = 1:length(obj.timelinePanels)
                panel = obj.timelinePanels{i};
                if isa(panel, panelClass)
                    panels{end + 1} = panel; %#ok<AGROW>
                end
            end
        end
        
        
        function vp = visibleVideoPanels(obj)
            vp = {};
            
            % Get the size of the top-level panel.
            set(obj.videosPanel, 'Units', 'pixels');
            videosPos = get(obj.videosPanel, 'Position');
            set(obj.videosPanel, 'Units', 'normalized');
            
            if videosPos(3) > 5
                % The splitter is open, check the panels.
                panels = obj.videoPanels;
                for i = 1:length(panels)
                    panel = panels{i};
                    if panel.visible
                        vp{end + 1} = panel; %#ok<AGROW>
                    end
                end
            end
        end
        
        
        function arrangeVideoPanels(obj, ~, ~)
            visibleVideoPanels = obj.visibleVideoPanels();
            
            % Get the size of the top-level panel.
            set(obj.videosPanel, 'Units', 'pixels');
            videosPos = get(obj.videosPanel, 'Position');
            set(obj.videosPanel, 'Units', 'normalized');
            
            if videosPos(3) < 5
                % The splitter has been collapsed, don't show the video panels.
                set(obj.videosPanel, 'Visible', 'off');
            else
                % The splitter is open, show the panels.
                set(obj.videosPanel, 'Visible', 'on');
                
                if ~isempty(visibleVideoPanels)
                    numPanels = length(visibleVideoPanels);
                    
                    % TODO: toolbar icon to allow column vs. row layout?
                    if true %visibleVideoPanels{1}.video.videoSize(1) < visibleVideoPanels{1}.video.videoSize(2)
                        % Arrange the videos in a column.
                        if true %isempty(visibleTimelinePanels)
                            panelHeight = floor(videosPos(4) / numPanels);
                            videoPanelWidth = videosPos(3);
                        else
                            panelHeight = floor(videosPos(4) / numPanels);
                            videoPanelWidth = floor(max(cellfun(@(panel) panelHeight / panel.video.videoSize(1) * panel.video.videoSize(2), visibleVideoPanels)));
                            videoWidth = max(cellfun(@(panel) panel.video.videoSize(1), visibleVideoPanels));
                            if videoWidth < videoPanelWidth
                                videoPanelWidth = videoWidth;
                            end
                        end
                        
                        for i = 1:numPanels
                            set(visibleVideoPanels{i}.panel, 'Position', [1, videosPos(4) - i * panelHeight, videoPanelWidth, panelHeight]);
                            visibleVideoPanels{i}.handleResize([], []);
                        end
                    else
                        % Arrange the videos in a row.
                    end
                end
            end
        end
        
        
        function showVideoPanels(obj, doShow)
            if nargin < 2
                doShow = true;
            end
            isShowing = (get(obj.splitter, 'DividerLocation') > 0.01);
            if isShowing ~= doShow
                try
                    obj.splitter.JavaComponent.getComponent(0).doClick();
                catch
                    % oh well?
                end
            end
        end
        
        
        function vp = visibleTimelinePanels(obj)
            vp = {};
            
            % Get the size of the top-level panel.
            set(obj.timelinesPanel, 'Units', 'pixels');
            timelinesPos = get(obj.timelinesPanel, 'Position');
            set(obj.timelinesPanel, 'Units', 'normalized');
            
            if timelinesPos(3) > 15
                % The splitter is open, check the panels.
                panels = obj.timelinePanels;
                for i = 1:length(panels)
                    panel = panels{i};
                    if panel.visible
                        vp{end + 1} = panel; %#ok<AGROW>
                    end
                end
            end
        end
        
        
        function arrangeTimelinePanels(obj, ~, ~)
            set(obj.splitter, 'DividerColor', 'red');
            
            visibleTimelinePanels = obj.visibleTimelinePanels();
            
            % Get the size of the top-level panel.
            set(obj.timelinesPanel, 'Units', 'pixels');
            timelinesPos = get(obj.timelinesPanel, 'Position');
            set(obj.timelinesPanel, 'Units', 'normalized');
            
            if timelinesPos(3) < 15
                % The splitter has been collapsed, don't show the timeline panels.
                set(obj.timelinesPanel, 'Visible', 'off');
            else
                % The splitter is open, show the panels.
                set(obj.timelinesPanel, 'Visible', 'on');
                
                if isempty(visibleTimelinePanels)
                    if ~isempty(obj.timeIndicatorPanel)
                        obj.timeIndicatorPanel.setVisible(false);
                    end
                else
                    % Arrange the other panels, leaving room at the top for the time indicator panel.
                    % Leave a one pixel gap between panels so there's a visible line between them.
                    timeIndicatorHeight = 13;
                    panelsHeight = timelinesPos(4) - timeIndicatorHeight;
                    numPanels = length(visibleTimelinePanels);
                    panelHeight = floor(panelsHeight / numPanels);
                    for i = 1:numPanels - 1
                        set(visibleTimelinePanels{i}.panel, 'Position', [4, timelinesPos(4) - timeIndicatorHeight - i * panelHeight, timelinesPos(3) - 3, panelHeight - 2]);
                        visibleTimelinePanels{i}.handleResize([], []);
                    end
                    lastPanelHeight = panelsHeight - panelHeight * (numPanels - 1) - 4;
                    set(visibleTimelinePanels{end}.panel, 'Position', [4, 2, timelinesPos(3) - 3, lastPanelHeight]);
                    visibleTimelinePanels{end}.handleResize([], []);
                    
                    obj.timeIndicatorPanel.setVisible(true);
                    set(obj.timeIndicatorPanel.panel, 'Position', [4, timelinesPos(4) - timeIndicatorHeight, timelinesPos(3) - 3, timeIndicatorHeight + 1]);
                end
            end
        end
        
        
        function showTimelinePanels(obj, doShow)
            if nargin < 2
                doShow = true;
            end
            isShowing = (get(obj.splitter, 'DividerLocation') < 0.99);
            if isShowing ~= doShow
                try
                    obj.splitter.JavaComponent.getComponent(1).doClick();
                catch
                    % oh well?
                end
            end
        end
        
        
        function handleNewWorkspace(obj, ~, ~) %#ok<INUSD>
            % Open a new window with a new controller object.
            % TODO: stagger the window so it doesn't land exactly on top of the existing one.
            TempoController();
        end
        
        
        function handleSelectAll(obj, ~, ~)
            % Select the full duration of all recordings.
            obj.selectedRange = [0 obj.duration -inf inf];
        end
        
        
        function handleSelectNone(obj, ~, ~)
            % Reduce the selection to just the current time.
            obj.selectedRange = [obj.currentTime obj.currentTime -inf inf];
        end
        
        
        function handlePlayMedia(obj, ~, ~)
            set(obj.playMediaTool, 'Enable', 'off');
            set(obj.pauseMediaTool, 'Enable', 'on');
            
            if obj.selectedRange(1) ~= obj.selectedRange(2)
                % Only play within the selected range.
                if obj.currentTime >= obj.selectedRange(1) && obj.currentTime < obj.selectedRange(2) - 0.1
                    idealRange = [obj.currentTime obj.selectedRange(2)];
                else
                    idealRange = [obj.selectedRange(1) obj.selectedRange(2)];
                end
            else
                % Play the whole song, starting at the current time unless it's at the end.
                if obj.currentTime < obj.duration
                    idealRange = [obj.currentTime obj.duration];
                else
                    idealRange = [0.0 obj.duration];
                end
            end
            
            obj.isPlayingMedia = true;
            
            % Start all of the audio players.
            for i = 1:length(obj.recordings)
                recording = obj.recordings{i};
                if isa(recording, 'AudioRecording') && ~recording.muted
                    playRange = round((idealRange + recording.timeOffset) * recording.sampleRate);
                    if playRange(1) == 0
                        playRange(1) = 1;
                    end
                    if playRange(2) > recording.duration * recording.sampleRate
                        playRange(2) = floor(recording.duration * recording.sampleRate);
                    end
                    player = recording.player();
                    if ~isempty(player)
                        play(player, playRange);
                    end
                end
            end
            
            obj.frameCount = 0;
            obj.mediaTimeSync = [idealRange now];
            start(obj.mediaTimer);
        end
        
        
        function handleMediaTimer(obj, ~, ~)
            offset = (now - obj.mediaTimeSync(3)) * 24 * 60 * 60;
            newTime = obj.mediaTimeSync(1) + offset;
            if newTime >= obj.mediaTimeSync(2)
                obj.handlePauseMedia([], []);
            else
                obj.currentTime = newTime;
                obj.centerDisplayAtTime(newTime);
            end
        end
        
        
        function handlePauseMedia(obj, hObject, ~)
            if obj.isPlayingMedia
                set(obj.playMediaTool, 'Enable', 'on');
                set(obj.pauseMediaTool, 'Enable', 'off');

                % Stop all of the audio players.
                for i = 1:length(obj.recordings)
                    recording = obj.recordings{i};
                    if isa(recording, 'AudioRecording') && ~recording.muted
                        player = recording.player();
                        if ~isempty(player)
                            stop(player);
                        end
                    end
                end
                stop(obj.mediaTimer);

                obj.isPlayingMedia = false;
                
                elapsedTime = (now - obj.mediaTimeSync(end)) * (24*60*60);
                fprintf('FPS: %g (%d/%g)\n', obj.frameCount / elapsedTime, obj.frameCount, elapsedTime);
                
                if isempty(hObject)
                    % The media played to the end without the user clicking the pause button.
                    if obj.selectedRange(1) ~= obj.selectedRange(2)
                        obj.currentTime = obj.selectedRange(2);
                    else
                        obj.currentTime = obj.duration;
                    end
                    obj.centerDisplayAtTime(obj.currentTime);
                else
                    obj.currentTime = obj.currentTime;
                    obj.centerDisplayAtTime(mean(obj.displayRange(1:2))); % trigger a refresh of timeline-based panels
                end
            end
        end
        
        
        function handleSaveScreenshot(obj, ~, ~)
            % TODO: determine if Ghostscript is installed and reduce choices if not.
            if isempty(obj.recordings)
                defaultPath = '';
                defaultName = 'Screenshot';
            else
                [defaultPath, defaultName, ~] = fileparts(obj.recordings{1}.filePath);
            end
            [fileName, pathName] = uiputfile({'*.pdf','Portable Document Format (*.pdf)'; ...
                                              '*.eps','Encapsulated Level 2 Color PostScript (*.eps)'; ...
                                              '*.png','PNG format (*.png)'; ...
                                              '*.jpg','JPEG format (*.jpg)'}, ...
                                             'Save a screen shot', ...
                                             fullfile(defaultPath, [defaultName '.pdf']));

            if ~isnumeric(fileName)
                if ismac
                    % Make sure export_fig can find Ghostscript if it was installed via MacPorts.
                    prevEnv = getenv('DYLD_LIBRARY_PATH');
                    setenv('DYLD_LIBRARY_PATH', ['/opt/local/lib:' prevEnv]);
                end
                
                % Determine the list of axes to export.
                axesToSave = [obj.timeIndicatorPanel.axes];
                visibleVideoPanels = obj.visibleVideoPanels();
                for i = 1:length(visibleVideoPanels)
                    axesToSave(end + 1) = visibleVideoPanels{i}.axes; %#ok<AGROW>
                end
                visibleTimelinePanels = obj.visibleTimelinePanels();
                for i = 1:length(visibleTimelinePanels)
                    axesToSave(end + 1) = visibleTimelinePanels{i}.axes; %#ok<AGROW>
%                    visibleTimelinePanels{i}.showSelection(false);
                end
                
                [~,~,e]=fileparts(fileName);
                switch e
                  case '.pdf'
                    print(obj.figure, '-dpdf', '-painters', fullfile(pathName, fileName));
                  case '.eps'
                    print(obj.figure, '-depsc2', '-painters', fullfile(pathName, fileName));
                  case '.png'
                    print(obj.figure, '-dpng', fullfile(pathName, fileName));
                  case '.jpg'
                    print(obj.figure, '-djpeg', fullfile(pathName, fileName));
                end
%                export_fig(fullfile(pathName, fileName), '-opengl', '-a1');  %, axesToSave);

                % Show the current selection again.
                for i = 1:length(visibleTimelinePanels)
                    visibleTimelinePanels{i}.showSelection(true);
                end
                
                if ismac
                    setenv('DYLD_LIBRARY_PATH', prevEnv);
                end
            end
        end
        
        
        function handleToggleWaveforms(obj, hObject, ~)
            obj.showWaveforms = ~obj.showWaveforms;
            for i = 1:length(obj.timelinePanels)
                panel = obj.timelinePanels{i};
                if isa(panel, 'WaveformPanel')
                    panel.setVisible(obj.showWaveforms);
                end
            end
            
            obj.arrangeTimelinePanels();
            
            if isempty(hObject)
                set(obj.showWaveformsTool, 'State', obj.toolStates{obj.showWaveforms + 1});
            else
                setpref('Tempo', 'ShowWaveforms', obj.showWaveforms);
            end
        end
        
        
        function handleToggleSpectrograms(obj, hObject, ~)
            obj.showSpectrograms = ~obj.showSpectrograms;
            for i = 1:length(obj.timelinePanels)
                panel = obj.timelinePanels{i};
                if isa(panel, 'SpectrogramPanel')
                    panel.setVisible(obj.showSpectrograms);
                end
            end
            
            obj.arrangeTimelinePanels();
            
            if isempty(hObject)
                set(obj.showSpectrogramsTool, 'State', obj.toolStates{obj.showSpectrograms + 1});
            else
                setpref('Tempo', 'ShowSpectrograms', obj.showSpectrograms);
            end
        end
        
        
        function handleToggleFeatures(obj, hObject, ~)
            obj.showFeatures = ~obj.showFeatures;
            for i = 1:length(obj.timelinePanels)
                panel = obj.timelinePanels{i};
                if isa(panel, 'FeaturesPanel')
                    panel.setVisible(obj.showFeatures);
                end
            end
            
            obj.arrangeTimelinePanels();
            
            if isempty(hObject)
                set(obj.showFeaturesTool, 'State', obj.toolStates{obj.showFeatures + 1});
            else
                setpref('Tempo', 'ShowFeatures', obj.showFeatures);
            end
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
                    waitfor(warndlg({'Could not automatically pop up the detectors toolbar menu.', '', 'Please click the small arrow next to the icon instead.'}, 'Tempo', 'modal'));
                end
            else
                detectorClassName = obj.detectorClassNames{index};
                
                constructor = str2func(detectorClassName);
                detector = constructor(obj);
                
                if detector.editSettings()
%TODO               addContextualMenu(detector);
                    
                    detector.startProgress();
                    try
                        if obj.selectedRange(2) > obj.selectedRange(1)
                            n = detector.detectFeatures(obj.selectedRange);
                        else
                            n = detector.detectFeatures([0.0 obj.duration]);
                        end
                        detector.endProgress();
                        
                        if n == 0
                            waitfor(msgbox('No features were detected.', detectorClassName, 'warn', 'modal'));
                        else
                            obj.reporters{end + 1} = detector;
                            obj.timelinePanels{end + 1} = FeaturesPanel(detector);

                            obj.arrangeTimelinePanels();
                            
                            obj.showTimelinePanels(true);
                            
                            obj.needsSave = true;
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
                reporter = featurePanel.reporter;
                
                % Remove the panel.
                obj.timelinePanels(cellfun(@(x) x == featurePanel, obj.timelinePanels)) = [];
                delete(featurePanel);
                obj.arrangeTimelinePanels();
                
                % Remove the panel's reporter.
                obj.reporters(cellfun(@(x) x == reporter, obj.reporters)) = [];
                delete(reporter);
                
% TODO:                handles = updateFeatureTimes(handles);

                for j = 1:length(obj.timelinePanels)
                    panel = obj.timelinePanels{j};
                    if isa(panel, 'SpectrogramPanel')
                        panel.deleteAllReporters();
                    end
                end
                
                obj.needsSave = true;
            end
        end
        
        
        function centerDisplayAtTime(obj, timeCenter)
            if isempty(obj.displayRange) && ~isempty(obj.recordings)
                obj.windowSize = 0.001;
                newRange = [0 obj.recordings{1}.duration 0 floor(obj.recordings{1}.sampleRate / 2)];
            else
                newRange = obj.displayRange;
            end

            timeWindowRadius = obj.duration / obj.zoom / 2;
            if timeCenter - timeWindowRadius < 0
                newRange(1:2) = [0, timeWindowRadius * 2];
            elseif timeCenter + timeWindowRadius > obj.duration
                newRange(1:2) = [obj.duration - timeWindowRadius * 2, obj.duration];
            else
                newRange(1:2) = [timeCenter - timeWindowRadius, timeCenter + timeWindowRadius];
            end

            obj.displayRange = newRange;
        end
        
        
        function selectRange(obj, range)
            obj.selectedRange = range;
            
            obj.currentTime = range(1);
            
            % TODO: Move the selection into view if necessary
%             newRange = ...
%             obj.displayRange = newRange;
        end
        
        
        function setZoom(obj, zoom)
            if zoom < 1
                obj.zoom = 1;
            else
                obj.zoom = zoom;
            end
            
            % Center all of the timeline-based panels on the selection.
            obj.centerDisplayAtTime(mean(obj.selectedRange(1:2)));
            
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
        
        
        function handleZoomToSelection(obj, ~, ~)
            selectionLength = abs(obj.selectedRange(2) - obj.selectedRange(1));
            if selectionLength > 0
                % Zoom the timelines so the selection exactly fits in the panels.
                obj.setZoom(obj.duration / selectionLength);
            else
                % Keep the current zoom but center the selection line.
                obj.centerDisplayAtTime(mean(obj.selectedRange(1:2)));
            end
        end
        
        
        function handleResize(obj, ~, ~)
            pos = get(obj.figure, 'Position');
            
            set(obj.splitterPanel, 'Position', [1, 16, pos(3), pos(4) - 16]);
            set(obj.timeSlider, 'Position', [1, 0, pos(3) + 1, 16]);
            
            obj.needsSave = true;
        end
        
        
        function pointer = resizePointer(obj, xConstraint, yConstraint)
            % Cursor names:
            %  topl  top   topr
            %  left fleur  right
            %  botl bottom botr
            if obj.panelSelectingTime.showsFrequencyRange && strcmp(yConstraint, 'min')
                pointer = 'bot';
            elseif obj.panelSelectingTime.showsFrequencyRange && strcmp(yConstraint, 'max')
                pointer = 'top';
            else
                pointer = '';
            end
            if strcmp(xConstraint, 'min')
                if isempty(pointer)
                    pointer = 'left';
                else
                    pointer = [pointer 'l'];
                end
            elseif strcmp(xConstraint, 'max')
                if isempty(pointer)
                    pointer = 'right';
                else
                    pointer = [pointer 'r'];
                end
            else
                if isempty(pointer)
                    pointer = 'fleur';
                elseif strcmp(pointer, 'bot')
                    pointer = [pointer 'tom'];
                end
            end
        end
        
        
        function handleMouseButtonDown(obj, ~, ~)
            if strcmp(get(gcf, 'SelectionType'), 'alt')
                return  % Don't change the current time or selection when control/right clicking.
            end
            
            clickedObject = get(obj.figure, 'CurrentObject');
            
            % TODO: allow panels to handle clicks on their objects?
            %
            %     handled = panel{i}.handleMouseDown(...);
            %     if ~handled
            %         ...
            
            for i = 1:length(obj.timelinePanels)
                timelinePanel = obj.timelinePanels{i};
                if clickedObject == timelinePanel.axes
                    clickedPoint = get(clickedObject, 'CurrentPoint');
                    clickedTime = clickedPoint(1, 1);
                    if timelinePanel.showsFrequencyRange
                        % Get the frequency from the clicked point.
                        % TODO: this doesn't work if the spectrogram is hidden when zoomed out.  Probably just need to have YLim set.
                        clickedFreq = clickedPoint(1, 2);
                    else
                        % Pick a dummy frequency at the middle of the selected range.
                        if isinf(obj.selectedRange(3)) && isinf(obj.selectedRange(4))
                            clickedFreq = 0;
                        else
                            clickedFreq = mean(obj.selectedRange(3:4));
                        end
                    end
                    if strcmp(get(gcf, 'SelectionType'), 'extend')
                        % Extend the time range.
                        if obj.currentTime == obj.selectedRange(1) || obj.currentTime ~= obj.selectedRange(2)
                            obj.selectedRange(1:2) = sort([obj.selectedRange(1) clickedTime]);
                        else
                            obj.selectedRange(1:2) = sort([clickedTime obj.selectedRange(2)]);
                        end
                        
                        % Extend the frequency range if appropriate.
                        if timelinePanel.showsFrequencyRange && ~isinf(obj.selectedRange(3)) && ~isinf(obj.selectedRange(4))
                            if clickedFreq < obj.selectedRange(3)
                                obj.selectedRange(3) = clickedFreq;
                            else
                                obj.selectedRange(4) = clickedFreq;
                            end
                        else
                            obj.selectedRange(3:4) = [-inf inf];
                        end
                    else
                        obj.panelSelectingTime = timelinePanel;
                        obj.originalSelectedRange = obj.selectedRange;
                        if clickedTime > obj.selectedRange(1) && clickedTime < obj.selectedRange(2) && ...
                           clickedFreq > obj.selectedRange(3) && clickedFreq < obj.selectedRange(4)
                            % The user clicked inside of the existing selection, figure out which part was clicked on.
                            % TODO: only allow mid/mid if box is too small?
                            
                            if timelinePanel.showsFrequencyRange && isinf(obj.selectedRange(3))
                                obj.selectedRange(3:4) = obj.displayRange(3:4);
                            end
                            
                            axesPos = get(timelinePanel.axes, 'Position');
                            timeMargin = 10 * (obj.displayRange(2) - obj.displayRange(1)) / (axesPos(3) - axesPos(1));
                            freqMargin = 10 * (obj.displayRange(4) - obj.displayRange(3)) / (axesPos(4) - axesPos(2));
                            if clickedTime < obj.selectedRange(1) + timeMargin && clickedTime < obj.selectedRange(2) - timeMargin
                                obj.mouseConstraintTime = 'min';
                            elseif clickedTime > obj.selectedRange(2) - timeMargin && clickedTime > obj.selectedRange(1) + timeMargin
                                obj.mouseConstraintTime = 'max';
                            else
                                obj.mouseConstraintTime = 'mid';
                            end
                            if clickedFreq < obj.selectedRange(3) + freqMargin && clickedFreq < obj.selectedRange(4) - freqMargin
                                obj.mouseConstraintFreq = 'min';
                            elseif clickedFreq > obj.selectedRange(4) - freqMargin && clickedFreq > obj.selectedRange(3) + freqMargin
                                obj.mouseConstraintFreq = 'max';
                            else
                                obj.mouseConstraintFreq = 'mid';
                            end
                        else
                            % The user clicked outside of the existing selection.
                            if timelinePanel.showsFrequencyRange
                                obj.selectedRange = [clickedTime clickedTime clickedFreq clickedFreq];
                            else
                                obj.selectedRange = [clickedTime clickedTime -inf inf];    %obj.displayRange(3:4)];
                            end
                            obj.originalSelectedRange = obj.selectedRange;
                            obj.mouseConstraintTime = 'max';
                            obj.mouseConstraintFreq = 'max';
                            obj.currentTime = clickedTime;
                        end
                        obj.mouseOffset = [clickedTime - obj.selectedRange(1), clickedFreq - obj.selectedRange(3)];
                    end
                    
                    break
                end
            end
        end
        
        
        function updateSelectedRange(obj)
            clickedPoint = get(obj.panelSelectingTime.axes, 'CurrentPoint');
            clickedTime = clickedPoint(1, 1);
            clickedFreq = clickedPoint(1, 2);
            newRange = obj.originalSelectedRange;
            
            xConstraint = obj.mouseConstraintTime;
            if strcmp(obj.mouseConstraintTime, 'min')
                newRange(1) = clickedTime;
            elseif strcmp(obj.mouseConstraintTime, 'mid') && strcmp(obj.mouseConstraintFreq, 'mid')
                width = obj.originalSelectedRange(2) - obj.originalSelectedRange(1);
                newRange(1) = clickedTime - obj.mouseOffset(1);
                newRange(2) = newRange(1) + width;
            elseif strcmp(obj.mouseConstraintTime, 'max')
                newRange(2) = clickedTime;
            end
            
            % Check if the drag has flipped over the y axis.
            if newRange(2) < newRange(1)
                newRange(1:2) = [newRange(2) newRange(1)];
                if strcmp(obj.mouseConstraintTime, 'min')
                    xConstraint = 'max';
                else
                    xConstraint = 'min';
                end
            end
            
            yConstraint = obj.mouseConstraintFreq;
            if obj.panelSelectingTime.showsFrequencyRange
                if strcmp(obj.mouseConstraintFreq, 'min')
                    newRange(3) = clickedFreq;
                elseif strcmp(obj.mouseConstraintFreq, 'mid') && strcmp(obj.mouseConstraintTime, 'mid')
                    if ~isinf(newRange(3)) && ~isinf(newRange(3))
                        height = obj.originalSelectedRange(4) - obj.originalSelectedRange(3);
                        newRange(3) = clickedFreq - obj.mouseOffset(2);
                        newRange(4) = newRange(3) + height;
                    end
                elseif strcmp(obj.mouseConstraintFreq, 'max')
                    newRange(4) = clickedFreq;
                end
                
                % Check if the drag has flipped over the x axis.
                if newRange(4) < newRange(3)
                    newRange(3:4) = [newRange(4) newRange(3)];
                    if strcmp(obj.mouseConstraintFreq, 'min')
                        yConstraint = 'max';
                    else
                        yConstraint = 'min';
                    end
                end
            end
            
            set(gcf, 'Pointer', obj.resizePointer(xConstraint, yConstraint));
            
            % If the current time was at the beginning or end of the selection then keep it there.
            if obj.currentTime == obj.selectedRange(1)
                obj.currentTime = newRange(1);
            elseif obj.currentTime == obj.selectedRange(2)
                obj.currentTime = newRange(2);
            end
            
            obj.selectedRange = newRange;
        end
        
        
        function handleMouseMotion(obj, varargin)
            if ~isempty(obj.panelSelectingTime)
                obj.updateSelectedRange();
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
                obj.updateSelectedRange();
                if obj.selectedRange(3) == obj.selectedRange(4)
                    obj.selectedRange(3:4) = [-inf inf];
                end
                obj.panelSelectingTime = [];
                set(gcf, 'Pointer', 'arrow');
            end
        end
        
        
        function handleKeyPress(obj, ~, keyEvent)
            if ~strcmp(keyEvent.Key, 'space')
                % Let one of the panels handle the event.
                % If the video panels are open they get first dibs.
                visiblePanels = horzcat(obj.visibleVideoPanels(), obj.visibleTimelinePanels());
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
                visiblePanels = horzcat(obj.visibleTimelinePanels(), obj.visibleVideoPanels());
                for i = 1:length(visiblePanels)
                    if visiblePanels{i}.keyWasReleased(keyEvent)
                        break
                    end
                end
            end
        end
        
        
        function handleTimeSliderChanged(obj, ~, ~)
            if get(obj.timeSlider, 'Value') ~= obj.displayRange(1)
                obj.centerDisplayAtTime(get(obj.timeSlider, 'Value'));
            end
        end
        
        
        function handleTimeWindowChanged(obj, ~, ~)
            % Adjust the step and page sizes of the time slider.
            stepSize = 1 / obj.zoom;
            curMax = get(obj.timeSlider, 'Max');
            newValue = mean(obj.displayRange(1:2));
            set(obj.timeSlider, 'SliderStep', [stepSize / 50.0 stepSize], ...
                                'Value', newValue, ...
                                'Max', max(curMax, newValue));
        end
        
        
        function handleOpenFile(obj, ~, ~)
            [fileNames, pathName] = uigetfile('*.*', 'Select an audio or video file to open', 'MultiSelect', 'on');
            
            if ischar(fileNames)
                fileNames = {fileNames};
            elseif isnumeric(fileNames)
                fileNames = {};
            end
            
            nothingWasOpen = isempty(obj.recordings);
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
                
                [~, ~, ext] = fileparts(fileName);
                if strcmp(ext, '.tempo')
                    if isempty(obj.recordings) && isempty(obj.reporters)
                        % Nothing has been done in this controller so load the workspace here.
                        target = obj;
                    else
                        % Open the workspace in a new controller.
                        target = TempoController();
                    end
                    target.openWorkspace(fullPath);
                    somethingOpened = true;
                    continue
                end
                
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
                                
                                % Open any recordings that the importer queued up.
                                for recording = obj.recordingsToAdd
                                    if isa(recording, 'AudioRecording')
                                        obj.addAudioRecording(recording);
                                    elseif isa(recording, 'VideoRecording')
                                        obj.addVideoRecording(recording);
                                    end
                                end
                                obj.recordingsToAdd = {};
                                
                                if n == 0
                                    waitfor(msgbox('No features were imported.', obj.importerTypeNames{index}, 'warn', 'modal'));
                                else
                                    obj.reporters{end + 1} = importer;
                                    obj.timelinePanels{end + 1} = FeaturesPanel(importer);
                                    
                                    obj.arrangeTimelinePanels();
                                    
                                    somethingOpened = true;
                                end
                            catch ME
                                importer.endProgress();
                                obj.importing = false;
                                obj.recordingsToAdd = {};
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
                    for j = 1:length(obj.recordingClassNames)
                        if eval([obj.recordingClassNames{j} '.canLoadFromPath(''' strrep(fullPath, '''', '''''') ''')'])
                            set(obj.figure, 'Pointer', 'watch'); drawnow
                            constructor = str2func(obj.recordingClassNames{j});
                            recording = constructor(obj, fullPath);
                            if isa(recording, 'AudioRecording')
                                obj.addAudioRecording(recording);
                                somethingOpened = true;
                            elseif isa(recording, 'VideoRecording')
                                obj.addVideoRecording(recording);
                                somethingOpened = true;
                            end
                            set(obj.figure, 'Pointer', 'arrow'); drawnow
                            break
                        end
                    end
                catch ME
                    set(obj.figure, 'Pointer', 'arrow'); drawnow
                    if ~strcmp(ME.identifier, 'Tempo:UserCancelled')
                        warndlg(sprintf('Error opening media file:\n\n%s', ME.message));
                        rethrow(ME);
                    end
                end
            end
            
            if somethingOpened
                obj.updateOverallDuration();
                
                if nothingWasOpen
                    if isempty(obj.videoPanels)
                        % Hide the video half of the splitter.
                        obj.showVideoPanels(false);
                    elseif isempty(obj.timelinePanels)
                        % Hide the video half of the splitter.
                        obj.showTimelinePanels(false);
                    end
                end
                
                obj.needsSave = true;
            elseif ~isempty(fileNames)
                warndlg('Tempo does not know how to open that kind of file.');
            end
        end
        
        
        function addAudioRecording(obj, recording)
            if obj.importing
                % There seems to be a bug in MATLAB where you can't create new axes while a waitbar is open.
                % Queue the recording to be added after the waitbar has gone away.
                obj.recordingsToAdd{end + 1} = recording;
            else
                if isempty(obj.recordings) && isempty(obj.savePath)
                    set(obj.figure, 'Name', ['Tempo: ' recording.name]);
                end
                
                obj.recordings{end + 1} = recording;
                
                panel = WaveformPanel(obj, recording);
                obj.timelinePanels{end + 1} = panel;
                panel.setVisible(obj.showWaveforms);
                
                panel = SpectrogramPanel(obj, recording);
                obj.timelinePanels{end + 1} = panel;
                panel.setVisible(obj.showSpectrograms);
                
                obj.arrangeTimelinePanels();
                
                addlistener(recording, 'timeOffset', 'PostSet', @(source, event)handleRecordingDurationChanged(obj, source, event));
            end
        end
        
        
        function addVideoRecording(obj, recording)
            if obj.importing
                % There seems to be a bug in MATLAB where you can't create new axes while a waitbar is open.
                % Queue the recording to be added after the waitbar has gone away.
                obj.recordingsToAdd{end + 1} = recording;
            else
                if isempty(obj.recordings)
                    set(obj.figure, 'Name', ['Tempo: ' recording.name]);
                end
                
                obj.recordings{end + 1} = recording;
                
                panel = VideoPanel(obj, recording);
                obj.videoPanels{end + 1} = panel;
                
                obj.arrangeVideoPanels();
                
                addlistener(recording, 'timeOffset', 'PostSet', @(source, event)handleRecordingDurationChanged(obj, source, event));
            end
        end
        
        
        function updateOverallDuration(obj)
            obj.duration = max([cellfun(@(r) r.duration, obj.recordings) cellfun(@(r) r.duration, obj.reporters)]);
            
            set(obj.timeSlider, 'Max', obj.duration);
            
            % Alter the zoom so that the same window of time is visible.
            if isempty(obj.displayRange)
                obj.setZoom(1);
            else
                obj.setZoom(obj.duration / (obj.displayRange(2) - obj.displayRange(1)));
            end
            
            obj.centerDisplayAtTime(mean(obj.displayRange(1:2))); % trigger a refresh of timeline-based panels
        end
        
        
        function handleRecordingDurationChanged(obj, ~, ~)
            obj.updateOverallDuration();
        end
        
        
        function saved = handleExportSelection(obj, ~, ~)
           saved = false;
            
            % Figure out a default save location and name.
            if isempty(obj.recordings)
                filePath = '';
                fileName = 'Workspace';
            else
                [filePath, fileName, ~] = fileparts(obj.recordings{1}.filePath);
            end
            [fileName, filePath] = uiputfile('*.mp4', 'Export Selection', fullfile(filePath, fileName));
            if ~eq(fileName, 0)
                exportPath = fullfile(filePath, fileName);
                [~, fileName, ~] = fileparts(fileName); % strip off the extension
                set(obj.figure, 'Name', ['Tempo: ' fileName]);
            end
            
            if ~isempty(exportPath)
                try
                    h=waitbar(0,'');
                    c=fileparts(mfilename('fullpath'));
                    if ismac
                      c=fullfile(c, 'ThirdParty', 'ffmpeg', 'ffmpeg_mac ');
                    elseif ispc
                      c=fullfile(c, 'ThirdParty', 'ffmpeg', 'ffmpeg_win.exe ');
                    elseif isunix
                      c=fullfile(c, 'ThirdParty', 'ffmpeg', 'ffmpeg_linux ');
                    end
                    f=cell(1,length(obj.recordings));
                    for i=1:length(obj.recordings)
                        h=waitbar(i/(length(obj.recordings)+1),h,['Processing ' obj.recordings{i}.name]);
                        set(findall(h,'type','text'),'Interpreter','none');
                        f{i}=obj.recordings{i}.saveData;
                        c=[c '-i ' f{i} ' ']; %#ok<AGROW>
                    end
                    c=[c '-acodec copy -vcodec copy ''' exportPath ''''];
                    waitbar(length(obj.recordings)/(length(obj.recordings)+1),h,['Processing '  exportPath]);
                    [s,~]=system(c);
                    if s
                      close(h);
                      ME=MException('problem with system(''ffmpeg'')');
                      throw(ME);
                    end
                    waitbar(1,h,'Deleting temporary files');
                    for i=1:length(obj.recordings)
                      delete(f{i});
                    end
                    close(h);
                catch ME
                    waitfor(warndlg(['Could not export the selection. (' ME.message ')'], 'Tempo', 'modal'));
                end
            end
        end
        
        
        function saved = handleSaveWorkspace(obj, ~, ~)
            saved = false;
            
            if isempty(obj.savePath)
                % Figure out a default save location and name.
                if isempty(obj.recordings)
                    filePath = '';
                    fileName = 'Workspace';
                else
                    [filePath, fileName, ~] = fileparts(obj.recordings{1}.filePath);
                end
                [fileName, filePath] = uiputfile({'*.tempo', 'Tempo Workspace'}, 'Save Tempo Workspace', fullfile(filePath, fileName));
                if ~eq(fileName, 0)
                    obj.savePath = fullfile(filePath, fileName);
                    [~, fileName, ~] = fileparts(fileName); % strip off the extension
                    set(obj.figure, 'Name', ['Tempo: ' fileName]);
                end
            end
            
            if ~isempty(obj.savePath)
                try
                    obj.saveWorkspace(obj.savePath);
                    obj.needsSave = false;
                    saved = true;
                catch ME
                    waitfor(warndlg(['Could not save the workspace. (' ME.message ')'], 'Tempo', 'modal'));
                end
            end
        end
        
        
        function saveWorkspace(obj, filePath)
            s.displayRange = obj.displayRange;
            s.selectedRange = obj.selectedRange;
            s.currentTime = obj.currentTime;
            s.windowSize = obj.windowSize;
            
            s.recordings = obj.recordings;

            s.reporters = obj.reporters;

            s.windowPosition = get(obj.figure, 'Position');
            s.mainSplitter.orientation = get(obj.splitter, 'Orientation');
            s.mainSplitter.location = get(obj.splitter, 'DividerLocation');
            
            s.showWaveforms = obj.showWaveforms;
            s.showSpectrograms = obj.showSpectrograms;
            s.showFeatures = obj.showFeatures;

            save(filePath, '-struct', 's');
        end
        
        
        function openWorkspace(obj, filePath)
            % TODO: Create a new controller if the current one has recordings open?
            %       Allow "importing" a workspace to add it to the current one?
            
            set(obj.figure, 'Pointer', 'watch'); drawnow
            
            obj.savePath = filePath;
            [~, fileName, ~] = fileparts(filePath);
            set(obj.figure, 'Name', ['Tempo: ' fileName]);
            
            s = load(filePath, '-mat');
            
            % TODO: check if the window still fits on screen?
            set(obj.figure, 'Position', s.windowPosition);
            
            if isfield(s, 'mainSplitter')
                % TODO: set vertical orientation once supported
                if s.mainSplitter.location < 0.01
                    obj.showVideoPanels(false);
                elseif s.mainSplitter.location > 0.99
                    obj.showTimelinePanels(false);
                else
                    obj.showVideoPanels(true);
                    obj.showTimelinePanels(true);
                    set(obj.splitter, 'DividerLocation', s.mainSplitter.location);
                end
            end
            
            if obj.showWaveforms ~= s.showWaveforms
                obj.handleToggleWaveforms([])
            end
            if obj.showSpectrograms ~= s.showSpectrograms
                obj.handleToggleSpectrograms([])
            end
            if obj.showFeatures ~= s.showFeatures
                obj.handleToggleFeatures([])
            end
            
            % Load the recordings.
            obj.recordings = s.recordings;
            for i = 1:length(obj.recordings)
                recording = obj.recordings{i};
                recording.controller = obj;
                recording.loadData();
                if isa(recording, 'AudioRecording')
                    panel = WaveformPanel(obj, recording);
                    obj.timelinePanels{end + 1} = panel;
                    panel.setVisible(obj.showWaveforms);

                    panel = SpectrogramPanel(obj, recording);
                    obj.timelinePanels{end + 1} = panel;
                    panel.setVisible(obj.showSpectrograms);
                elseif isa(recording, 'VideoRecording')
                    panel = VideoPanel(obj, recording);
                    obj.videoPanels{end + 1} = panel;
                end
            end
            
            % Load the detectors and importers.
            if isfield(s, 'reporters')
                obj.reporters = s.reporters;
                for i = 1:length(obj.reporters)
                    reporter = obj.reporters{i};
                    reporter.controller = obj;
                    obj.timelinePanels{end + 1} = FeaturesPanel(reporter);
                    obj.timelinePanels{end}.setVisible(obj.showFeatures);
                end
            end
            
            obj.windowSize = s.windowSize;
            obj.displayRange = s.displayRange;
            obj.selectedRange = s.selectedRange;
            obj.currentTime = s.currentTime;
            
            obj.duration = max([cellfun(@(r) r.duration, obj.recordings) cellfun(@(r) r.duration, obj.reporters)]);
                
            set(obj.timeSlider, 'Max', obj.duration);
                
            % Alter the zoom so that the same window of time is visible.
            if isempty(obj.displayRange)
                obj.setZoom(1);
            else
                obj.setZoom(obj.duration / (obj.displayRange(2) - obj.displayRange(1)));
            end
                
            obj.centerDisplayAtTime(mean(obj.displayRange(1:2))); % trigger a refresh of timeline-based panels
            
            obj.arrangeVideoPanels();
            obj.arrangeTimelinePanels();
            
            set(obj.figure, 'Pointer', 'arrow'); drawnow
        end
        
        
        function handleClose(obj, ~, ~)
            obj.handlePauseMedia([]);
            
            if obj.needsSave
                button = questdlg('Do you want to save the changes to the Tempo workspace?', 'Tempo', 'Don''t Save', 'Cancel', 'Save', 'Save');
                if strcmp(button, 'Save')
                    if ~obj.handleSaveWorkspace()
                        return
                    end
                elseif strcmp(button, 'Cancel')
                    return;
                else
                    % TODO: obj.needsSave = false?
                end
            end
            
            delete(obj.mediaTimer);
            
            % Remember the window position.
            setpref('Tempo', 'MainWindowPosition', get(obj.figure, 'Position'));
            
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
            % Directory plug-in
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
        elseif ~pluginDirs(i).isdir && strcmp(pluginDirs(i).name(end-1:end), '.m')
            % Single file plug-in
            className = pluginDirs(i).name(1:end-2);
            try
                eval([className '.initialize()'])
                pluginCount = pluginCount + 1;
                classNames{pluginCount} = className;
                typeNames{pluginCount} = className;
            catch
                % It's a .m file but not a plug-in.
            end
        end
    end
    classNames = classNames(1:pluginCount);
    typeNames = typeNames(1:pluginCount);
end