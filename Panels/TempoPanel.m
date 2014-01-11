classdef TempoPanel < handle
    
    properties
        controller
        panel
        
        titleColor = [0.75 0.75 0.75]
        titlePanel
        closeButton
        showHideButton
        showIcon
        hideIcon
        actionButton
        actionMenu
        titleText
        
        panelType = ''
        title = ''
        
        axes
        
        isHidden = false
        
        listeners = {}
    end
    
    methods
        
        function obj = TempoPanel(controller)
            obj.controller = controller;
            
            if isa(obj, 'VideoPanel')
                parentPanel = obj.controller.videosPanel;
            else
                parentPanel = obj.controller.timelinesPanel;
            end
            
            obj.panel = uipanel(parentPanel, ...
                'BorderType', 'none', ...
                'BorderWidth', 0, ...
                'BackgroundColor', 'white', ...
                'SelectionHighlight', 'off', ...
                'Units', 'pixels', ...
                'Position', [-200 -200 100 100], ...
                'ResizeFcn', @(source, event)handleResize(obj, source, event));
            
            obj.titlePanel = uipanel(obj.panel, ...
                'BorderType', 'none', ...
                'BorderWidth', 0, ...
                'BackgroundColor', obj.titleColor, ...
                'SelectionHighlight', 'off', ...
                'Units', 'pixels', ...
                'Position', [0 0 100 16]);
            
            if obj.hasTitleBarControls()
                [tempoRoot, ~, ~] = fileparts(mfilename('fullpath'));
                [tempoRoot, ~, ~] = fileparts(tempoRoot);
                iconRoot = fullfile(tempoRoot, 'Icons');
                
                obj.closeButton = uicontrol(...
                    'Parent', obj.titlePanel, ...
                    'Style', 'pushbutton', ...
                    'CData', double(imread(fullfile(iconRoot, 'PanelClose.png'))) / 255.0, ...
                    'Units', 'pixels', ...
                    'Position', [4 3 12 12], ...
                    'Callback', @(hObject,eventdata)handleClosePanel(obj, hObject, eventdata), ...
                    'Tag', 'closeButton');
                
                obj.showIcon = double(imread(fullfile(iconRoot, 'PanelShow.png'))) / 255.0;
                obj.hideIcon = double(imread(fullfile(iconRoot, 'PanelHide.png'))) / 255.0;
                obj.showHideButton = uicontrol(...
                    'Parent', obj.titlePanel, ...
                    'Style', 'pushbutton', ...
                    'CData', obj.hideIcon, ...
                    'Units', 'pixels', ...
                    'Position', [20 3 12 12], ...
                    'Callback', @(hObject,eventdata)handleHidePanel(obj, hObject, eventdata), ...
                    'Tag', 'hideButton');
                
                obj.actionMenu = uicontextmenu;
                uimenu(obj.actionMenu, ...
                    'Label', 'Hide', ...
                    'Callback', @(hObject,eventdata)handleHidePanel(obj, hObject, eventdata));
                uimenu(obj.actionMenu, ...
                    'Label', 'Close', ...
                    'Callback', @(hObject,eventdata)handleClosePanel(obj, hObject, eventdata));
                obj.addActionMenuItems(obj.actionMenu);
                obj.actionButton = uicontrol(...
                    'Parent', obj.titlePanel, ...
                    'Style', 'pushbutton', ...
                    'CData', double(imread(fullfile(iconRoot, 'PanelAction.png'))) / 255.0, ...
                    'Units', 'pixels', ...
                    'Position', [36 3 12 12], ...
                    'Callback', @(hObject,eventdata)handleShowActionMenu(obj, hObject, eventdata), ...
                    'UIContextMenu', obj.actionMenu, ...
                    'Tag', 'actionButton');
                
                obj.titleText = uicontrol(...
                    'Parent', obj.titlePanel, ...
                    'Style', 'text', ...
                    'String', [obj.panelType ': ' obj.title], ...
                    'Units', 'pixels', ...
                    'Position', [52 3 100 12], ...
                    'HorizontalAlignment', 'left', ...
                    'ForegroundColor', obj.titleColor * 0.25, ...
                    'BackgroundColor', obj.titleColor, ...
                    'HitTest', 'off', ...
                    'Tag', 'titleText');
            end
            
            obj.axes = axes('Parent', obj.panel, ...
                'Units', 'pixels', ...
                'Position', [0 0 100 - 16 100], ...
                'XLim', [0 1], ...
                'XTick', [], ...
                'YLim', [0 1], ...
                'YTick', []); %#ok<CPROP>
            
            obj.createControls([100 - 16, 100]);
            
            % Add listeners so we know when the current time and selection change.
            obj.listeners{end + 1} = addlistener(obj.controller, 'currentTime', 'PostSet', @(source, event)handleCurrentTimeChanged(obj, source, event));
            
            obj.handleCurrentTimeChanged([], []);
        end
        
        
        function h = hasTitleBarControls(obj) %#ok<MANU>
            h = true;
        end
        
        
        function addActionMenuItems(obj, actionMenu) %#ok<INUSD>
            % Sub-classes can override to add additional items to the action menu.
        end
        
        
        function handleResize(obj, ~, ~)
            % Get the pixel size of the whole panel.
            prevUnits = get(obj.panel, 'Units');
            set(obj.panel, 'Units', 'pixels');
            panelPos = get(obj.panel, 'Position');
            set(obj.panel, 'Units', prevUnits);
            
            panelPos(4) = panelPos(4) + 1;
            
            if obj.hasTitleBarControls()
                % Position the title panel.
                titlePos = [0, panelPos(4) - 16, panelPos(3), 16];
                set(obj.titlePanel, 'Position', titlePos);
                
                % Resize the text box.
                set(obj.titleText, 'Position', [52, 3, titlePos(3) - 52 - 5,  12]);
                axesPos = [0, 0, panelPos(3), panelPos(4) - 16];
            else
                axesPos = [0, 0, panelPos(3), panelPos(4)];
            end
            
            % Position the axes within the panel.
            set(obj.axes, 'Position', axesPos, 'Units', 'pixels');
            
            % Let subclasses reposition their controls.
            obj.resizeControls(axesPos(3:4));
        end
        
        
        function handleClosePanel(obj, ~, ~)
            % TODO: How to undo this?  The uipanel gets deleted...
            
            obj.controller.closePanel(obj);
        end
        
        
        function handleHidePanel(obj, ~, ~)
            obj.controller.hidePanel(obj);
        end
        
        
        function handleShowPanel(obj, ~, ~)
            obj.controller.showPanel(obj);
        end
        
        
        function handleShowActionMenu(obj, ~, ~)
            % Show the contextual menu at
            mousePos = get(obj.controller.figure, 'CurrentPoint');
            set(obj.actionMenu, ...
                'Position', mousePos, ...
                'Visible', 'on');
        end
        
        
        function createControls(obj, panelSize) %#ok<INUSD>
        end
        
        
        function resizeControls(obj, panelSize) %#ok<INUSD>
        end
        
        
        function setHidden(obj, hidden)
            if obj.isHidden ~= hidden
                obj.isHidden = hidden;
                
                if obj.isHidden
                    set(obj.showHideButton, 'CData', obj.showIcon, 'Callback', @(hObject,eventdata)handleShowPanel(obj, hObject, eventdata));
                    set(obj.titleText, 'ForegroundColor', obj.titleColor * 0.5);
                    
                    % Hide the axes and all of its children.
                    set(obj.axes, 'Visible', 'off');
                    set(allchild(obj.axes), 'Visible', 'off');
                else
                    set(obj.showHideButton, 'CData', obj.hideIcon, 'Callback', @(hObject,eventdata)handleHidePanel(obj, hObject, eventdata));
                    set(obj.titleText, 'ForegroundColor', obj.titleColor * 0.25);
                    
                    % Show the axes and all of its children.
                    set(obj.axes, 'Visible', 'on');
                    set(allchild(obj.axes), 'Visible', 'on');
                    
                    % Make sure everything is in sync.
                    obj.handleCurrentTimeChanged([], []);
                end
            end
        end
        
        
        function setTitle(obj, title)
            obj.title = title;
            if ~isempty(obj.titleText)
                set(obj.titleText, 'String', [obj.panelType ': ' obj.title]);
            end
        end
        
        
        function handled = keyWasPressed(obj, event) %#ok<INUSD>
            handled = false;
        end
        
        
        function handled = keyWasReleased(obj, event) %#ok<INUSD>
            handled = false;
        end
        
        
        function handleCurrentTimeChanged(obj, ~, ~)
            if ~obj.isHidden
                obj.currentTimeChanged();
            end
        end
        
        
        function currentTimeChanged(obj) %#ok<MANU>
            % TODO: make abstract?
        end
        
        
        function close(obj)
            % Subclasses can override this if they need to do anything more.
            
            % Delete any listeners.
            cellfun(@(x) delete(x), obj.listeners);
            
            % Remove the uipanel from the figure.
            if ishandle(obj.panel)
                delete(obj.panel);
            end
        end
        
    end
    
end