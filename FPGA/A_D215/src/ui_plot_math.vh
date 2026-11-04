// Bounded geometry helpers. All results stay within the 1024x600 raster.
function [9:0] ui_wave_y;
 input [7:0] amplitude;reg signed [10:0] scaled;
 begin scaled=$signed(amplitude)*11'sd5;ui_wave_y=11'sd238-(scaled>>>3);end
endfunction
