// Ziemia z dziurą na rzekę pod mostem (etap 3a urozmaiceń) - włączana przez
// xr_main tylko w pobliżu mostu; ten sam wygląd co ground.gdshader.
shader_type spatial;

#include "res://shaders/world_wrap.gdshaderinc"
#define RIVER_HOLE
#include "res://shaders/ground_body.gdshaderinc"
