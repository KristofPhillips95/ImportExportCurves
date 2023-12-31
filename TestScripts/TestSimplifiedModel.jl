include("ImportExport/model_builder.jl")
using Gurobi


scenario = "National Trends"
endtime = 24 * 100
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000

m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets_simplified!(m,scenario,year,CY,[],[country])
process_parameters_simplified!(m,scenario,year,CY,[country])
process_time_series!(m,scenario,year,CY_ts, true)
remove_capacity_country!(m,country,true)


build_NTC_investment_model!(m,endtime,VOLL,0.1,0.07,true)
optimize!(m)



#Check if production + net_import equals demand 
country = "DE00"
c_import = [sum(JuMP.value.(m.ext[:variables][:import][country,neighbor,t] for neighbor in m.ext[:sets][:connections][country])) for t in 1:endtime]
c_export = [sum(JuMP.value.(m.ext[:variables][:export][country,neighbor,t] for neighbor in m.ext[:sets][:connections][country])) for t in 1:endtime]
demand = [m.ext[:timeseries][:demand][country][t] for t in 1:endtime]
curtailment = [JuMP.value.(m.ext[:variables][:curtailment][country,t] ) for t in 1:endtime]
load_shedding = [JuMP.value.(m.ext[:variables][:load_shedding][country,t] ) for t in 1:endtime]

tech = "OCGT"
productions = Dict(tech => [JuMP.value.(m.ext[:variables][:production][country,tech,t]) for t in 1:endtime] for tech in m.ext[:sets][:technologies][country] )
# Extract x values (time periods)
x = 1:length(productions["OCGT"])

# Initialize a variable to store the stacked production values
y_stacked = c_import - c_export
plt = plot(y_stacked,label = "net_import")

# Create a stacked line plot
# for tech  in ["PV", "w_on", "w_off", "CCGT", "OCGT"]
for tech  in keys(productions)
    # Add the production values to the stacked values
    y_stacked += productions[tech]

    #plot!(x, y_stacked, label = tech)
    plot!(x,productions[tech], label = tech)
end

scatter!(x,demand + curtailment - load_shedding - y_stacked,label = "Sum of it all")
# Customize the plot
plot!(xlabel = "Time", ylabel = "Production", legend = :topright)

# Display the plot
display(plt)

ls_tot = sum(JuMP.value.(m.ext[:variables][:load_shedding]))

dem_tot = sum(sum([m.ext[:timeseries][:demand][country][t] for t in 1:endtime] for country in m.ext[:sets][:countries]))

ls_tot/dem_tot