include("ImportExport/model_builder.jl")
include("ImportExport/curve_based_model_builder.jl")
using Gurobi
using CSV
using Plots
endtime = 48
CY = 1984
CY_ts = 2012
VOLL = 8000
country = "BE00"
transport_cost = 0.1


sc_ty_tuples = [("National Trends",2025), ("National Trends",2030),("National Trends",2040),("Distributed Energy",2030),("Distributed Energy",2040)]
sc_ty_tuple = sc_ty_tuples[1]
scenario = sc_ty_tuple[1]
year = sc_ty_tuple[2]


m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY,[],[country])
#We start by redefining the sets here, to remove unnecessary countries. 
all_countries = [key for key in keys(m.ext[:sets][:technologies])]
define_sets!(m,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
process_parameters!(m,scenario,year,CY,[country])
process_time_series!(m,scenario,year,CY_ts)
remove_capacity_country!(m,country)

#Obtain trade availability ts 
curves = CSV.read("Results/TradeCurves/import_price_curvesNational Trends_2025_CY_2012_48.csv",DataFrame)
curves = CSV.read("Results/TradeCurves//import_price_curves$(scenario)_$(year)_CY_$(CY_ts)_$(endtime).csv",DataFrame)

add_availability_curves_to_model!(m,curves)

build_single_trade_curve_investment_model!(m,endtime,VOLL,transport_cost)


#build_isolated_investment_model!(m,endtime,VOLL)

#Inspect some stuff
m.ext[:constraints][:import_restrictions]
m.ext[:expressions][:trade_cost]
m.ext[:constraints][:demand_met]["BE00",1]

optimize!(m)

trade_prices = m.ext[:sets][:trade_prices]
timesteps = collect(1:endtime)
imports = [JuMP.value.(sum(m.ext[:variables][:import]["BE00",p,t] for p in trade_prices)) for t in timesteps]
exports = [JuMP.value.(sum(m.ext[:variables][:export]["BE00",p,t] for p in trade_prices)) for t in timesteps]

#Visualise total imports and exports
plot(imports)
plot!(exports)

#Visualise import/export at different prices 
plot()
for price in trade_prices 
    imports_p = [JuMP.value.(m.ext[:variables][:import]["BE00",price,t]) for t in timesteps]
    plot!(imports_p,label=("imp",price))
    exports_p = [JuMP.value.(m.ext[:variables][:export]["BE00",price,t]) for t in timesteps]
    plot!(exports_p,label=("exp",price))
end
plot!()


# Check that trade levels do not exceed maxima
for price in trade_prices 
    imports_p = [JuMP.value.(m.ext[:variables][:import]["BE00",price,t]) for t in timesteps]
    @assert all(imports_p .<= m.ext[:timeseries][:trade][:import][price])

    exports_p = [JuMP.value.(m.ext[:variables][:export]["BE00",price,t]) for t in timesteps]
    @assert all(exports_p .<= m.ext[:timeseries][:trade][:export][price])
end


# Check that trade at a certain price occurs only if the more interesting price is saturated

#Import
prev_price = trade_prices[1]

for price in trade_prices[2:end]
    imports_prev_price = [JuMP.value.(m.ext[:variables][:import]["BE00",prev_price,t]) for t in timesteps]
    imports_this_price = [JuMP.value.(m.ext[:variables][:import]["BE00",price,t]) for t in timesteps]

    prev_equal_to_max = (imports_prev_price .== m.ext[:timeseries][:trade][:import][prev_price])
    @assert all(prev_equal_to_max .& (imports_this_price .> 0) .== (imports_this_price.>0))

    if sum((imports_this_price.>0)) >0
        prev_price = price
    end
end

#Export
prev_price = trade_prices[end]
for price in reverse(trade_prices[1:end-1])
    print(price)
    exports_prev_price = [JuMP.value.(m.ext[:variables][:export]["BE00",prev_price,t]) for t in timesteps]
    exports_this_price = [JuMP.value.(m.ext[:variables][:export]["BE00",price,t]) for t in timesteps]

    prev_equal_to_max = (exports_prev_price .== m.ext[:timeseries][:trade][:export][prev_price])
    @assert all(prev_equal_to_max .& (exports_this_price .> 0) .== (exports_this_price.>0))

    if sum((exports_this_price.>0)) >0
        prev_price = price
    end
end

# Check that total trade cost is equal to the expected value 

total_transport_cost = sum(JuMP.value.(m.ext[:expressions][:trade_cost]))
expected_total_transport_cost = sum(JuMP.value.(m.ext[:variables][:import])) * transport_cost + sum(JuMP.value.(m.ext[:variables][:export])) * transport_cost

@assert(total_transport_cost - expected_total_transport_cost < 0.0001)

#TODO Check that total cost of import and export is equal to the expected value 


#########################
# Comparison of models ##
#########################

#Start the building process of 3 models 
m1 = Model(optimizer_with_attributes(Gurobi.Optimizer))
m2 = Model(optimizer_with_attributes(Gurobi.Optimizer))
m3 = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY,[],[country])
all_countries = [key for key in keys(m.ext[:sets][:technologies])]

define_sets!(m1,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
define_sets!(m2,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
define_sets!(m3,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])

process_parameters!(m1,scenario,year,CY,[country])
process_parameters!(m2,scenario,year,CY,[country])
process_parameters!(m3,scenario,year,CY,[country])

process_time_series!(m1,scenario,year,CY_ts)
process_time_series!(m2,scenario,year,CY_ts)
process_time_series!(m3,scenario,year,CY_ts)

remove_capacity_country!(m1,country)
remove_capacity_country!(m2,country)
remove_capacity_country!(m3,country)


#Now we differentiate between the three models

#m1 is a simple isolated model
build_isolated_investment_model!(m1,endtime,VOLL)

#For m2, and m3 we go through the process of adding the trade curves
#Obtain trade availability ts 
curves = CSV.read("Results/TradeCurves//import_price_curves$(scenario)_$(year)_CY_$(CY_ts)_$(endtime).csv",DataFrame)
add_availability_curves_to_model!(m2,curves)
add_availability_curves_to_model!(m3,curves)

#But for m2, we set all availabilities to 0, so we expect the same result as m1
trade_prices = m2.ext[:sets][:trade_prices]

for price in trade_prices
    m2.ext[:timeseries][:trade][:import][price] .= 0 
    m2.ext[:timeseries][:trade][:export][price] .= 0 
end
m2.ext[:timeseries][:trade][:import]


build_single_trade_curve_investment_model!(m2,endtime,VOLL,transport_cost)

#m3 is the actual model with trade curves, so we expect a lower objective here
build_single_trade_curve_investment_model!(m3,endtime,VOLL,transport_cost)

optimize!(m1)
optimize!(m2)
optimize!(m3)

@assert (JuMP.objective_value(m1) - JuMP.objective_value(m2) == 0)
@assert (JuMP.objective_value(m2) - JuMP.objective_value(m3) > 0)