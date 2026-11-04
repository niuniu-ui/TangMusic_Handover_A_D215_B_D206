cd [file dirname [info script]]
open_project TangMusic_B_Clean_UI_D206.gprj
set_option -top_module studio_board_b
set_option -output_base_name TangMusic_B_Clean_UI_D206
set_option -user_code 0000D206
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -timing_driven 1
set_option -correct_hold_violation 1
set_option -route_option 2
set_option -inc_place 0
set_option -inc_pnr 0
run pnr
exit
