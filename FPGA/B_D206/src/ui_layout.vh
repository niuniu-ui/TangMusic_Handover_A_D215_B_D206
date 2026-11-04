// Generated from actual 1024x600 artwork geometry.
function [4:0] ui_key_at;
 input [9:0] tx,ty;
 begin ui_key_at=5'd31;
  if(tx>=119 && tx<183 && ty>=438 && ty<534) ui_key_at=5'd0;
  if(tx>=188 && tx<251 && ty>=438 && ty<534) ui_key_at=5'd2;
  if(tx>=256 && tx<320 && ty>=438 && ty<534) ui_key_at=5'd4;
  if(tx>=325 && tx<388 && ty>=438 && ty<534) ui_key_at=5'd5;
  if(tx>=393 && tx<456 && ty>=438 && ty<534) ui_key_at=5'd7;
  if(tx>=461 && tx<525 && ty>=438 && ty<534) ui_key_at=5'd9;
  if(tx>=530 && tx<593 && ty>=438 && ty<534) ui_key_at=5'd11;
  if(tx>=598 && tx<661 && ty>=438 && ty<534) ui_key_at=5'd12;
  if(tx>=168 && tx<207 && ty>=438 && ty<497) ui_key_at=5'd1;
  if(tx>=235 && tx<274 && ty>=438 && ty<497) ui_key_at=5'd3;
  if(tx>=371 && tx<410 && ty>=438 && ty<497) ui_key_at=5'd6;
  if(tx>=439 && tx<478 && ty>=438 && ty<497) ui_key_at=5'd8;
  if(tx>=506 && tx<545 && ty>=438 && ty<497) ui_key_at=5'd10;
 end
endfunction
