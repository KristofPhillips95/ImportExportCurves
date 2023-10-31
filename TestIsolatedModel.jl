include("ImportExport/model_builder.jl")
using Gurobi

scenario = "National Trends"
endtime = 240
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000



m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY,)


all_countries = [key for key in keys(m.ext[:sets][:technologies])]

define_sets!(m,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])