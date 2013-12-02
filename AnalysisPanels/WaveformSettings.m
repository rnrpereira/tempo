function edited = WaveformSettings(waveformPanel, varargin)
    handles.waveformPanel = waveformPanel;
    
    handles.figure = dialog(...
        'Units', 'points', ...
        'Name', 'Waveform Settings', ...
        'Position', [100, 100, 350, 256], ...
        'Visible', 'off', ...
        'WindowKeyPressFcn', @(hObject, eventdata)handleWindowKeyPress(hObject, eventdata, guidata(hObject)));
    
    uicontrol(...
        'Parent', handles.figure, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [10 224 330 16], ...
        'String',  ['Audio file: ' waveformPanel.audio.name], ...
        'TooltipString', waveformPanel.audio.filePath, ...
        'Style', 'text');
    
    
    % Create the "Vertical scaling" panel.
    scalingPanel = uipanel(handles.figure, ...
        'Title', 'Vertical scaling', ...
        'Units', 'points', ...
        'Position', [10 70 330 140], ...
        'FontSize', 12);
    handles.scalingButtons = uibuttongroup(...
        'Parent', scalingPanel, ...
        'Units', 'points', ...
        'Position', [0 35 300 60], ...
        'SelectionChangeFcn', @(hObject,eventdata)handleSetVerticalScalingMethod(hObject,eventdata,guidata(hObject)), ...
        'BorderType', 'none');
    handles.scaleByEntireWaveformButton = uicontrol(...
        'Parent', handles.scalingButtons, ...
        'Units', 'points', ...
        'Position', [10 60 300 18], ...
        'FontSize', 12, ...
        'String',  'Based on the entire waveform', ...
        'Style', 'radiobutton');
    handles.scaleByDisplayedWaveformButton = uicontrol(...
        'Parent', handles.scalingButtons, ...
        'Units', 'points', ...
        'Position', [10 30 300 18], ...
        'FontSize', 12, ...
        'String',  'Based on the displayed portion of the waveform', ...
        'Style', 'radiobutton');
    handles.scaleManuallyButton = uicontrol(...
        'Parent', handles.scalingButtons, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'Position', [10 0 300 18], ...
        'String',  'Manually:', ...
        'Style', 'radiobutton');
    handles.scaleButtons = [handles.scaleByEntireWaveformButton handles.scaleByDisplayedWaveformButton handles.scaleManuallyButton];
    handles.manualSlider = uicontrol(...
        'Parent', scalingPanel, ...
        'Units', 'points', ...
        'Position', [34 10 206 20], ...
        'Min', 0.0, ...
        'Max', 2.0, ...
        'Value', waveformPanel.verticalScalingValue, ...
        'Style', 'slider');
    handles.manualEdit = uicontrol(...
        'Parent', scalingPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [250 10 60 26], ...
        'String',  num2str(waveformPanel.verticalScalingValue, '%#4.3g'), ...
        'Style', 'edit');
    
    % Create the remaining controls.
    handles.applyToAllCheckbox = uicontrol(...
        'Parent', handles.figure,...
        'Units', 'points', ...
        'FontSize', 12, ...
        'Position', [10 40 180 18], ...
        'Callback', @(hObject,eventdata)handleApplyToAllWaveforms(hObject,eventdata,guidata(hObject)), ...
        'String',  'Apply to all waveforms', ...
        'Style', 'checkbox');
    
    handles.cancelButton = uicontrol(...
        'Parent', handles.figure,...
        'Units', 'points', ...
        'Position', [350 - 10 - 56 - 10 - 56 10 56 20], ...
        'Callback', @(hObject,eventdata)handleCancelSettings(hObject,eventdata,guidata(hObject)), ...
        'String', 'Cancel');
    
    handles.saveButton = uicontrol(...
        'Parent', handles.figure,...
        'Units', 'points', ...
        'Position', [350 - 10 - 56 10 56 20], ...
        'Callback', @(hObject,eventdata)handleSaveSettings(hObject,eventdata,guidata(hObject)), ...
        'String', 'Save');
    
    % Center and show the window.
    movegui(handles.figure, 'center');
    set(handles.figure, 'Visible', 'on');
    
    if verLessThan('matlab', '7.12.0')
        addlistener(handles.manualSlider, 'Action', @handleManualSliderValueChanged);
    else
        addlistener(handles.manualSlider, 'ContinuousValueChange', @handleManualSliderValueChanged);
    end
    
    % Make a copy of all waveforms' scaling settings in case the user cancels or turns off "apply to all".
    handles.waveformPanels = waveformPanel.controller.panelsOfClass('WaveformPanel');
    handles.originalVerticalScalingMethods = cellfun(@(x) x.verticalScalingMethod, handles.waveformPanels);
    handles.originalVerticalScalingValues = cellfun(@(x) x.verticalScalingValue, handles.waveformPanels);
    
    guidata(handles.figure, handles);
    
    % Show the settings of this waveform panel.
    setScalingMethodAndOrValue(waveformPanel.verticalScalingMethod, waveformPanel.verticalScalingValue, handles);
    
    % Wait for the user to cancel or save.
    uiwait(handles.figure);
    
    if ishandle(handles.figure)
        handles = guidata(handles.figure);
        edited = handles.edited;
        close(handles.figure);
    else
        edited = false;
    end
end


function handleManualSliderValueChanged(hObject, ~)
    % Convert the slider value to a scaling value.
    newValue = get(hObject, 'Value');
    if newValue < 1.0
        newValue = (newValue * 0.9) + 0.1;
    else
        newValue = (newValue - 1.0) * 9.0 + 1.0;
    end
    
    setScalingMethodAndOrValue([], newValue, guidata(hObject));
end


function a = applyToAllWaveforms(handles)
    a = get(handles.applyToAllCheckbox, 'Value') == get(handles.applyToAllCheckbox, 'Max');
end


function setScalingMethodAndOrValue(method, value, handles)
    % Update the UI controls.
    if ~isempty(method)
        set(handles.scalingButtons, 'SelectedObject', handles.scaleButtons(method));
        if handles.scaleButtons(method) == handles.scaleManuallyButton
            set([handles.manualSlider, handles.manualEdit], 'Enable', 'on');
        else
            set([handles.manualSlider, handles.manualEdit], 'Enable', 'off');
        end
    end
    if ~isempty(value)
        % Convert the scaling value to a slider value.
        % [0.1 1.0] maps to [0.0 1.0] and [1.0 10.0] maps to [1.0 2.0]
        if value < 1.0
            sliderValue = (value - 0.1) / 0.9;
        else
            sliderValue = (value - 1.0) / 9.0 + 1.0;
        end
        
        set(handles.manualSlider, 'Value', sliderValue);
        set(handles.manualEdit, 'String', num2str(value, '%#4.3g'));
    end
    
    if applyToAllWaveforms(handles)
        % Update all of the waveform panels' displays.
        for i = 1:length(handles.waveformPanels)
            handles.waveformPanels{i}.setVerticalScalingMethodAndOrValue(method, value);
        end
    else
        % Update only the current waveform panel's display.
        handles.waveformPanel.setVerticalScalingMethodAndOrValue(method, value);
    end
end


function handleWindowKeyPress(hObject, eventData, handles)
    % Handle the return and escape keys.
    if strcmp(eventData.Key, 'return')
        handleSaveSettings(hObject, eventData, handles);
    elseif strcmp(eventData.Key, 'escape')
        handleCancelSettings(hObject, eventData, handles);
    end
end


function handleSetVerticalScalingMethod(~, ~, handles)
    selectedButton = get(handles.scalingButtons, 'SelectedObject');
    newMethod = find(handles.scaleButtons == selectedButton);
    
    setScalingMethodAndOrValue(newMethod, [], handles);
end


function handleApplyToAllWaveforms(~, ~, handles)
    % Reset the scaling method and value of just this or all of the waveforms 
    % now that the checkbox has a different value.
    setScalingMethodAndOrValue(handles.waveformPanel.verticalScalingMethod, ...
                               handles.waveformPanel.verticalScalingValue, handles);
    
    if ~applyToAllWaveforms(handles)
        % Reset all of the other waveform panels to their original settings.
        for i = 1:length(handles.waveformPanels)
            if handles.waveformPanels{i} ~= handles.waveformPanel
                handles.waveformPanels{i}.setVerticalScalingMethodAndOrValue(handles.originalVerticalScalingMethods(i), ...
                                                                             handles.originalVerticalScalingValues(i));
            end
        end
    end
end


function handleCancelSettings(~, ~, handles)
    % Reset all of the waveform panels to their original settings.
    for i = 1:length(handles.waveformPanels)
        handles.waveformPanels{i}.setVerticalScalingMethodAndOrValue(handles.originalVerticalScalingMethods(i), ...
                                                                     handles.originalVerticalScalingValues(i));
    end
    
    handles.edited = false;
    guidata(handles.figure, handles);
    
    uiresume;
end


function handleSaveSettings(~, ~, handles)
    % Move focus off of any edit text so the changes are committed.
    uicontrol(handles.saveButton);
    
    handles.edited = true;
    guidata(handles.figure, handles);
    
    uiresume;
end
