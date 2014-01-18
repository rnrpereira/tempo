classdef FeaturesAnnotator < FeaturesReporter
    
    properties
        featureDefinitions
    end
    
    properties (Transient)
        rangeFeatureBeingAdded
        rangeFeatureStartTime
    end
    
    
    methods(Static)
        
        function n = typeName()
            n = 'Manual Annotations';
        end
        
        function ft = possibleFeatureTypes()
            % TODO: can't do this statically
            ft = {};
        end
        
    end
    
    
    methods
        
        function obj = FeaturesAnnotator(controller)
            obj = obj@FeaturesReporter(controller);
            
            obj.featureDefinitions(1).type = 'First leg';
            obj.featureDefinitions(1).hotKey = '1';
            obj.featureDefinitions(1).color = [1 0 0];
            obj.featureDefinitions(1).isRange = true;
            
            obj.featureDefinitions(2).type = 'Head grooming';
            obj.featureDefinitions(2).hotKey = 'h';
            obj.featureDefinitions(2).color = [0.5 0 0];
            obj.featureDefinitions(2).isRange = true;
            
            obj.featureDefinitions(3).type = 'Third leg';
            obj.featureDefinitions(3).hotKey = '3';
            obj.featureDefinitions(3).color = [0.5 0.5 0.25];
            obj.featureDefinitions(3).isRange = true;
            
            obj.featureDefinitions(4).type = 'Wing grooming';
            obj.featureDefinitions(4).hotKey = 'w';
            obj.featureDefinitions(4).color = [0 0.25 0.5];
            obj.featureDefinitions(4).isRange = true;
            
            obj.featureDefinitions(5).type = 'Abdominal grooming';
            obj.featureDefinitions(5).hotKey = 'a';
            obj.featureDefinitions(5).color = [0 0.25 0];
            obj.featureDefinitions(5).isRange = true;
            
        end
        
        
        function types = featureTypes(obj)
            % Override the base class so we show all types and preserve the order.
            types = {obj.featureDefinitions.type};
        end
        
        
        function edited = editSettings(obj) %#ok<MANU>
            % TODO
            
            edited = true;
        end
        
        
        function handled = keyWasPressedInPanel(obj, keyEvent, panel)
            handled = false;
            for i = 1:length(obj.featureDefinitions)
                featureDef = obj.featureDefinitions(i);
                if keyEvent.Character == featureDef.hotKey
                    feature = [];
                    
                    if featureDef.isRange
                        if panel.controller.isPlaying
                            % Allow the user to create a range feature during playback.
                            % Wait until the key release to add the feature.
                            obj.rangeFeatureBeingAdded = Feature(featureDef.type, panel.controller.currentTime);
                            obj.rangeFeatureBeingAdded.color = featureDef.color;
                        elseif panel.controller.selectedRange(2) > panel.controller.selectedRange(1)
                            % Add the current selection as a new feature.
                            feature = Feature(featureDef.type, panel.controller.selectedRange, 'color', featureDef.color);
                        else
                            % The selection is not a range.
                            beep
                        end
                    else
                        % Add a point feature at the start of the current time.
                        feature = Feature(featureDef.type, panel.controller.currentTime, ...
                                          'color', featureDef.color);
                    end
                    
                    if ~isempty(feature)
                        obj.addFeatures({feature});
                        
                        % TODO: select the feature?
                        
                        panel.controller.addUndoableAction(['Add ' feature.type], ...
                                                           @() obj.removeFeatures({feature}), ...
                                                           @() obj.addFeatures({feature}), ...
                                                           panel);
                        
                        handled = true;
                        break;
                    end
                    
                    handled = true;
                    break;
                end
            end
        end
        
        
        function handled = keyWasReleasedInPanel(obj, ~, panel)
            % Finish creating a range feature during playback.
            
            if ~isempty(obj.rangeFeatureBeingAdded)
                % Update the end time of the feature.
                obj.rangeFeatureBeingAdded.range(2) = panel.controller.currentTime;
                
                obj.addFeatures({obj.rangeFeatureBeingAdded});
                
                panel.controller.addUndoableAction(['Add ' obj.rangeFeatureBeingAdded.type], ...
                                                    @() obj.removeFeatures({obj.rangeFeatureBeingAdded}), ...
                                                    @() obj.addFeatures({obj.rangeFeatureBeingAdded}), ...
                                                    panel);
                
                obj.rangeFeatureBeingAdded = [];
                
                handled = true;
            else
                handled = false;
            end
        end
    end
    
end
