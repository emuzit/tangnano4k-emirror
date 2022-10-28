//Copyright (C)2014-2022 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.07 Education
//Created Time: 2022-10-28 17:47:14
create_clock -name DVP_PCLK -period 6.734 -waveform {0 3.367} [get_ports {DVP_PCLK}]
create_clock -name PX2_CLK -period 13.468 -waveform {0 6.734} [get_nets {px2_clk}]
