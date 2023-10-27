include("ImportExport/model_builder.jl")
using Gurobi


scenario = "National Trends"
endtime = 24*10
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000
CO2_price = 0.085

m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY)

all_countries = [key for key in keys(m.ext[:sets][:technologies])]

define_sets!(m,scenario,year,CY,all_countries[2:end] )

process_parameters!(m,scenario,year,CY)
process_time_series!(m,scenario,year,CY_ts)

m.ext[:sets]

build_NTC_model!(m,endtime,VOLL,0.1)


keys(m.ext[:sets][:technologies])
m.ext[:sets][:technologies]["BE00"]
m.ext[:parameters][:technologies]
m.ext[:timeseries][:demand]