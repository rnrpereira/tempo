function edited = SpectrogramSettings(spectrogramPanel, varargin)
    handles.spectrogramPanel = spectrogramPanel;
    
    handles.figure = dialog(...
        'Units', 'points', ...
        'Name', 'Spectrogram Settings', ...
        'Position', [100, 100, 350, 325], ...
        'Visible', 'off', ...
        'WindowKeyPressFcn', @(hObject, eventdata)handleWindowKeyPress(hObject, eventdata, guidata(hObject)));
    
    % Create the "Frequency Range" panel.
    frequencyPanel = uipanel(handles.figure, ...
        'Title', 'Frequency range (Hz)', ...
        'Units', 'points', ...
        'Position', [10 260 330 55], ...
        'FontSize', 12);
    uicontrol(...
        'Parent', frequencyPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [10 10 46 16], ...
        'String',  'Min:', ...
        'Style', 'text');
    handles.frequencyMinEdit = uicontrol(...
        'Parent', frequencyPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [40 6 65 26], ...
        'String',  num2str(spectrogramPanel.controller.displayRange(3), '%d'), ...
        'Callback', @(hObject,eventdata)handleFrequencyRangeEditValueChanged(hObject,eventdata,guidata(hObject)), ...
        'Style', 'edit');
    uicontrol(...
        'Parent', frequencyPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [165 10 46 16], ...
        'String',  'Max:', ...
        'Style', 'text');
    handles.frequencyMaxEdit = uicontrol(...
        'Parent', frequencyPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [195 6 65 26], ...
        'String',  num2str(spectrogramPanel.controller.displayRange(4), '%d'), ...
        'Callback', @(hObject,eventdata)handleFrequencyRangeEditChanged(hObject,eventdata,guidata(hObject)), ...
        'Style', 'edit');
    
    % Create the "FFT" panel.
    fftPanel = uipanel(handles.figure, ...
        'Title', 'FFT', ...
        'Units', 'points', ...
        'Position', [10 190 330 55], ...
        'FontSize', 12);
    uicontrol(...
        'Parent', fftPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [10 10 80 16], ...
        'String',  'Window size:', ...
        'Style', 'text');
    handles.fftWindowEdit = uicontrol(...
        'Parent', fftPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [90 6 65 26], ...
        'String',  num2str(spectrogramPanel.controller.windowSize * 1000, '%#6.3f'), ...
        'Callback', @(hObject,eventdata)handleFFTWindowEditValueChanged(hObject,eventdata,guidata(hObject)), ...
        'TooltipString', sprintf('Valid range: %g - 1000.0 msec', 64 / spectrogramPanel.audio.sampleRate * 1000), ...
        'Style', 'edit');
    uicontrol(...
        'Parent', fftPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [160 10 50 16], ...
        'String',  'msec', ...
        'Style', 'text');
    
    % Create the "Saturation" panel.
    saturationPanel = uipanel(handles.figure, ...
        'Title', 'Saturation', ...
        'Units', 'points', ...
        'Position', [10 50 330 120], ...
        'FontSize', 12);
    uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [10 76 40 16], ...
        'String',  'Low:', ...
        'Style', 'text');
    handles.lowSaturationSlider = uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'Position', [50 72 195 20], ...
        'Min', 0.0, ...
        'Max', 1.0, ...
        'Value', spectrogramPanel.saturation(1), ...
        'Style', 'slider');
    handles.lowSaturationEdit = uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [250 72 55 26], ...
        'String',  num2str(spectrogramPanel.saturation(1) * 100.0, '%#6.1f'), ...
        'Callback', @(hObject,eventdata)handleSaturationEditValueChanged(hObject,eventdata,guidata(hObject)), ...
        'Style', 'edit');
    uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [305 76 16 16], ...
        'String',  '%', ...
        'Style', 'text');
    uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [10 40 40 16], ...
        'String',  'High:', ...
        'Style', 'text');
    handles.highSaturationSlider = uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'Position', [50 36 195 20], ...
        'Min', 0.0, ...
        'Max', 1.0, ...
        'Value', spectrogramPanel.saturation(2), ...
        'Style', 'slider');
    handles.highSaturationEdit = uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'center', ...
        'Position', [250 36 55 26], ...
        'String',  num2str(spectrogramPanel.saturation(2) * 100.0, '%#6.1f'), ...
        'Callback', @(hObject,eventdata)handleSaturationEditValueChanged(hObject,eventdata,guidata(hObject)), ...
        'Style', 'edit');
    uicontrol(...
        'Parent', saturationPanel, ...
        'Units', 'points', ...
        'FontSize', 12, ...
        'HorizontalAlignment', 'left', ...
        'Position', [305 40 16 16], ...
        'String',  '%', ...
        'Style', 'text');
    handles.applyToAllCheckbox = uicontrol(...
        'Parent', saturationPanel,...
        'Units', 'points', ...
        'FontSize', 12, ...
        'Position', [10 10 180 18], ...
        'Callback', @(hObject,eventdata)handleApplyToAllSpectrograms(hObject,eventdata,guidata(hObject)), ...
        'String',  'Apply to all spectrograms', ...
        'Value', 1, ...
        'Style', 'checkbox');
    
    handles.useDefaultsButton = uicontrol(...
        'Parent', handles.figure,...
        'Units', 'points', ...
        'Position', [10 10 80 20], ...
        'Callback', @(hObject,eventdata)handleUseDefaults(hObject,eventdata,guidata(hObject)), ...
        'String', 'Use Defaults');
    
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
        addlistener(handles.lowSaturationSlider, 'Action', @handleSaturationSliderValueChanged);
        addlistener(handles.highSaturationSlider, 'Action', @handleSaturationSliderValueChanged);
    else
        addlistener(handles.lowSaturationSlider, 'ContinuousValueChange', @handleSaturationSliderValueChanged);
        addlistener(handles.highSaturationSlider, 'ContinuousValueChange', @handleSaturationSliderValueChanged);
    end
    
    % Make a copy of the original settings in case the user cancels or turns off "apply to all".
    handles.originalFrequencyRange = handles.spectrogramPanel.controller.displayRange(3:4);
    handles.originalFFTWindow = handles.spectrogramPanel.controller.windowSize;
    handles.spectrogramPanels = spectrogramPanel.controller.panelsOfClass('SpectrogramPanel');
    handles.originalSaturations = cellfun(@(x) x.saturation, handles.spectrogramPanels, 'UniformOutput', false);
    
    guidata(handles.figure, handles);
    
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


function handleFrequencyRangeEditChanged(~, ~, handles)
    minValue = str2double(get(handles.frequencyMinEdit, 'String'));
    maxValue = str2double(get(handles.frequencyMaxEdit, 'String'));
    
    if minValue < 0
        minValue = 0;
    elseif minValue > handles.spectrogramPanel.audio.sampleRate
        minValue = handles.spectrogramPanel.audio.sampleRate;
    end
    if maxValue < 0
        maxValue = 0;
    elseif maxValue > handles.spectrogramPanel.audio.sampleRate
        maxValue = handles.spectrogramPanel.audio.sampleRate;
    end
    % TODO: minValue >= maxValue?
    
    handles.spectrogramPanel.controller.displayRange(3:4) = [minValue maxValue];
end


function handleFFTWindowEditValueChanged(~, ~, handles)
    value = str2double(get(handles.fftWindowEdit, 'String')) / 1000.0;
    
    if value < 64 / handles.spectrogramPanel.audio.sampleRate
        value = 64 / handles.spectrogramPanel.audio.sampleRate;
    elseif value > 1.0
        value = 1.0;
    end
    
    handles.spectrogramPanel.controller.windowSize = value;
end


function handleSaturationSliderValueChanged(hObject, ~)
    handles = guidata(hObject);
    
    lowValue = get(handles.lowSaturationSlider, 'Value');
    highValue = get(handles.highSaturationSlider, 'Value');
    
    setSaturation([lowValue highValue], handles);
end


function handleSaturationEditValueChanged(~, ~, handles)
    lowValue = str2double(get(handles.lowSaturationEdit, 'String')) / 100.0;
    if lowValue < 0.0
        lowValue = 0.0;
    elseif lowValue > 1.0
        lowValue = 1.0;
    end
    highValue = str2double(get(handles.highSaturationEdit, 'String')) / 100.0;
    if highValue < 0.0
        highValue = 0.0;
    elseif highValue > 1.0
        highValue = 1.0;
    end
    
    setSaturation([lowValue highValue], handles);
end


function a = applyToAllSpectrograms(handles)
    a = get(handles.applyToAllCheckbox, 'Value') == get(handles.applyToAllCheckbox, 'Max');
end


function setFrequencyRange(frequencyRange, handles)
    set(handles.frequencyMinEdit, 'String', num2str(frequencyRange(1), '%d'));
    set(handles.frequencyMaxEdit, 'String', num2str(frequencyRange(2), '%d'));
    
    handles.spectrogramPanel.controller.displayRange(3:4) = frequencyRange;
end


function setFFTWindow(fftWindow, handles)
    set(handles.fftWindowEdit, 'String', num2str(fftWindow * 1000, '%#6.3f'));
    
    handles.spectrogramPanel.controller.windowSize = fftWindow;
end


function setSaturation(saturation, handles)
    % Update the UI controls.
    set(handles.lowSaturationSlider, 'Value', saturation(1));
    set(handles.lowSaturationEdit, 'String', num2str(saturation(1) * 100.0, '%#6.1f'));
    set(handles.highSaturationSlider, 'Value', saturation(2));
    set(handles.highSaturationEdit, 'String', num2str(saturation(2) * 100.0, '%#6.1f'));
    
    if applyToAllSpectrograms(handles)
        % Update all of the spectrogram panels' displays.
        for i = 1:length(handles.spectrogramPanels)
            handles.spectrogramPanels{i}.saturation = saturation;
        end
    else
        % Update only the current spectrogram panel's display.
        handles.spectrogramPanel.saturation = saturation;
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


function handleApplyToAllSpectrograms(~, ~, handles)
    % Reset the saturations of just this or all of the spectrograms 
    % now that the checkbox has a different value.
    lowValue = get(handles.lowSaturationSlider, 'Value');
    highValue = get(handles.highSaturationSlider, 'Value');
    
    setSaturation([lowValue highValue], handles);
    
    if ~applyToAllSpectrograms(handles)
        % Reset all of the other spectrogram panels to their original settings.
        for i = 1:length(handles.spectrogramPanels)
            if handles.spectrogramPanels{i} ~= handles.spectrogramPanel
                handles.spectrogramPanels{i}.saturation = handles.originalSaturations{i};
            end
        end
    end
end


function handleUseDefaults(~, ~, handles) 
    setFrequencyRange([100, handles.spectrogramPanel.audio.sampleRate / 2], handles);
    setFFTWindow(0.001, handles);
    setSaturation([0.01 0.99], handles);
end


function handleCancelSettings(~, ~, handles)
    % Reset all of the waveform panels to their original settings.
    handles.spectrogramPanel.controller.displayRange(3:4) = handles.originalFrequencyRange;
    handles.spectrogramPanel.controller.windowSize = handles.originalFFTWindow;
    for i = 1:length(handles.spectrogramPanels)
        handles.spectrogramPanels{i}.saturation = handles.originalSaturations{i};
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
