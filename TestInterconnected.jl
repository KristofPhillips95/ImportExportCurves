include("ImportExport/model_builder.jl")
using Gurobi
using Plots

scenario = "National Trends"
endtime = 24 * 10 
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000

results = DataFrame()

isolated = false
country = "BE00"

m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY,[],[country])

process_parameters!(m,scenario,year,CY,[country])
process_time_series!(m,scenario,year,CY_ts)
remove_capacity_country!(m,country)
build_NTC_investment_model!(m,endtime,VOLL,0.1,0.07)
optimize!(m)


#Check if production + net_import equals demand 
country_plot = "BE00"
plot_country_is_target = country_plot == country
c_import = [sum(JuMP.value.(m.ext[:variables][:import][country_plot,neighbor,t] for neighbor in m.ext[:sets][:connections][country_plot])) for t in 1:endtime]
c_export = [sum(JuMP.value.(m.ext[:variables][:export][country_plot,neighbor,t] for neighbor in m.ext[:sets][:connections][country_plot])) for t in 1:endtime]
demand = [m.ext[:timeseries][:demand][country_plot][t] for t in 1:endtime]
curtailment = [JuMP.value.(m.ext[:variables][:curtailment][country_plot,t] ) for t in 1:endtime]
load_shedding = [JuMP.value.(m.ext[:variables][:load_shedding][country_plot,t] ) for t in 1:endtime]

if plot_country_is_target
    productions = Dict(tech => [JuMP.value.(m.ext[:variables][:production][country_plot,tech,t]) for t in 1:endtime] for tech in m.ext[:sets][:technologies][country_plot] )
    charges = Dict(tech => [JuMP.value.(m.ext[:variables][:charge][country_plot,tech,t]) for t in 1:endtime] for tech in m.ext[:sets][:storage_technologies][country_plot] )
else
    productions = Dict(tech => [JuMP.value.(m.ext[:variables][:production][country_plot,tech,t]) for t in 1:endtime] for tech in m.ext[:sets][:investment_technologies][country_plot] )
end
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
if plot_country_is_target
    charges_stacked = zeros(endtime)
    for tech  in keys(charges)
        # Add the production values to the stacked values
        charges_stacked += charges[tech]

        #plot!(x, y_stacked, label = tech)
        plot!(x,charges[tech], label = string("charge " , tech))
    end
end
plot!(x,curtailment,label = "curtailment")
plot!(x,load_shedding,label = "load_shedding")
if plot_country_is_target
    scatter!(x,demand + curtailment + charges_stacked - load_shedding - y_stacked,label = "Sum of it all")
else
    scatter!(x,demand + curtailment - load_shedding - y_stacked,label = "Sum of it all")
end
# Customize the plot
plot!(xlabel = "Time", ylabel = "Production", legend = :topright,title = country_plot)

# Display the plot
display(plt)
savefig("Results/Figures/SanityCheck/Nodal_balance_$(country)_$(country_plot)")