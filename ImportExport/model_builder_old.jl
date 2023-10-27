## Step 0: Activate environment - ensure consistency accross computers
using Pkg
Pkg.activate(@__DIR__) # @__DIR__ = directory this script is in
Pkg.instantiate()
using JuMP
using DataFrames
using CSV

##
function define_sets!(m::Model,scenario::String,year::Int,CY::Int,excluded_nodes)

    #Initialize empty sets
    m.ext[:sets] = Dict()

    m.ext[:sets][:technologies] = Dict()
    m.ext[:sets][:dispatchable_technologies] = Dict()
    m.ext[:sets][:flat_run_technologies] = Dict()
    m.ext[:sets][:intermittent_technologies] = Dict()
    m.ext[:sets][:storage_technologies] = Dict()
    m.ext[:sets][:hydro_flow_technologies] = Dict()
    m.ext[:sets][:hydro_flow_technologies_without_pumping] = Dict()
    m.ext[:sets][:hydro_flow_technologies_with_pumping] = Dict()
    m.ext[:sets][:soc_technologies] = Dict()
    m.ext[:sets][:pure_storage_technologies] = Dict()
    m.ext[:sets][:connections] = Dict()

    #Technology type sets
    define_technology_type_sets!(m,scenario,year,CY,excluded_nodes)

    #Connection sets
    define_connection_sets!(m,scenario,year,CY)
end

function define_technology_type_sets!(m::Model,scenario::String,year::Int,CY::Int,excluded_nodes::Array=[])
    reading = CSV.read("Input Data\\gen_cap.csv",DataFrame)
    reading = reading[reading[!,"Scenario"] .== scenario,:]
    reading = reading[reading[!,"Year"] .== year,:]
    reading = reading[reading[!,"Climate Year"] .== CY,:]

    m.ext[:sets][:countries] = [country for country in setdiff(Set(reading[!,"Node"]),Set(excluded_nodes))]

    for country in m.ext[:sets][:countries]
        technologies = setdiff(Set(reading[reading[!,"Node"] .== country,:Generator_ID]),Set(["DSR"]))
        dispatchable_technologies = Set(reading[(reading[!,"Node"] .== country) .& (reading[!,"Super_type"] .== "Dispatchable") ,:Generator_ID])
        flat_run_technologies = Set(reading[(reading[!,"Node"] .== country) .& (reading[!,"Super_type"] .== "Flat") ,:Generator_ID])
        intermittent_technologies = Set(reading[(reading[!,"Node"] .== country) .& (reading[!,"Super_type"] .== "Intermittent") ,:Generator_ID])
        storage_technologies = Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "Storage") .| (reading[!,"Super_type"] .== "Storage_flow")) ,:Generator_ID])
        hydro_flow_technologies = Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "Storage_flow") .| (reading[!,"Super_type"] .== "ROR") .| (reading[!,"Super_type"] .== "RES") ),:Generator_ID])
        soc_technologies = Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "Storage_flow") .| (reading[!,"Super_type"] .== "Storage").| (reading[!,"Super_type"] .== "RES") .| (reading[!,"Super_type"] .== "ROR")),:Generator_ID])
        pure_storage_technologies = Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "Storage")),:Generator_ID])
        hydro_flow_technologies_without_pumping =  Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "RES") .| (reading[!,"Super_type"] .== "ROR")),:Generator_ID])
        hydro_flow_technologies_with_pumping =  Set(reading[(reading[!,"Node"] .== country) .& ((reading[!,"Super_type"] .== "Storage_flow")),:Generator_ID])


        m.ext[:sets][:technologies][country] = [tech for tech in technologies]

        m.ext[:sets][:dispatchable_technologies][country] = [tech for tech in dispatchable_technologies]
        m.ext[:sets][:flat_run_technologies][country] = [tech for tech in flat_run_technologies]

        m.ext[:sets][:intermittent_technologies][country] = [tech for tech in intermittent_technologies]
        m.ext[:sets][:storage_technologies][country] = [tech for tech in storage_technologies]
        m.ext[:sets][:hydro_flow_technologies][country] = [tech for tech in hydro_flow_technologies]
        m.ext[:sets][:soc_technologies][country] = [tech for tech in soc_technologies]
        m.ext[:sets][:pure_storage_technologies][country] = [tech for tech in pure_storage_technologies]
        m.ext[:sets][:hydro_flow_technologies_without_pumping][country] = [tech for tech in hydro_flow_technologies_without_pumping]
        m.ext[:sets][:hydro_flow_technologies_with_pumping][country] = [tech for tech in hydro_flow_technologies_with_pumping]

    end
end

function define_connection_sets!(m::Model,scenario::String,year::Int,CY::Int)
    reading_lines = CSV.read("Input Data\\lines.csv",DataFrame)
    reading_lines = reading_lines[reading_lines[!,"Scenario"] .== scenario,:]
    reading_lines = reading_lines[reading_lines[!,"Climate Year"] .== CY,:]
    reading_lines = reading_lines[reading_lines[!,"Year"] .== year,:]

    m.ext[:sets][:connections] = Dict(country => [] for country in m.ext[:sets][:countries])
    for country in m.ext[:sets][:countries]
        reading_lines_country = reading_lines[reading_lines[!,"Node1"] .== country,:]
        for other_country in intersect(reading_lines_country.Node2,m.ext[:sets][:countries])
            if !(other_country in m.ext[:sets][:connections][country])
                m.ext[:sets][:connections][country] = vcat(m.ext[:sets][:connections][country],other_country)
            end
            if !(country in m.ext[:sets][:connections][other_country])
                m.ext[:sets][:connections][other_country] = vcat(m.ext[:sets][:connections][other_country],country)
            end
        end
    end
end

##
function process_parameters!(m::Model,scenario::String,year::Int,CY::Int)
    countries = m.ext[:sets][:countries]
    technologies = m.ext[:sets][:technologies]
    connections = m.ext[:sets][:connections]

    m.ext[:parameters] = Dict()

    m.ext[:parameters][:technologies] = Dict()
    m.ext[:parameters][:connections] = Dict()
    m.ext[:parameters][:DSR] = Dict()
    m.ext[:parameters][:DSR][:capacities] = Dict()
    m.ext[:parameters][:DSR][:horizons] = Dict()

    #Power generation capacities
    m.ext[:parameters][:technologies][:capacities] = Dict()
    m.ext[:parameters][:technologies][:energy_capacities] = Dict()
    m.ext[:parameters][:technologies][:efficiencies] = Dict()
    m.ext[:parameters][:technologies][:VOM] = Dict()
    m.ext[:parameters][:technologies][:availabilities] = Dict()
    m.ext[:parameters][:technologies][:fuel_cost] = Dict()
    m.ext[:parameters][:technologies][:emissions] = Dict()

    m.ext[:parameters][:technologies][:total_gen] = Dict()


    process_power_generation_parameters!(m,scenario,year,CY,countries,technologies)
    process_line_capacities!(m,scenario,year,CY,countries)
    process_hydro_energy_capacities!(m,countries)
    process_battery_energy_capacities!(m,countries)
    process_DSR_capacities(m,countries,scenario,CY)
    process_flat_generation(m,countries,scenario,CY)
    process_co2_price(m,year)
end

function process_co2_price(m,year::Int64)
    reading_co2 = CSV.read("Input Data\\Techno-economic parameters\\co2_price.csv",DataFrame)
    m.ext[:parameters][:CO2_price] = reading_co2[1,string(year)]/1000

end
function process_power_generation_parameters!(m::Model,scenario::String,year::Int,CY::Int,countries,technologies)
    reading = CSV.read("Input Data\\gen_cap.csv",DataFrame)
    reading = reading[reading[!,"Scenario"] .== scenario,:]
    reading = reading[reading[!,"Year"] .== year,:]
    reading = reading[reading[!,"Climate Year"] .== CY,:]

    reading_technical = CSV.read("Input Data\\Techno-economic parameters\\Generator_efficiencies.csv",DataFrame)
    fuel_prices = CSV.read("Input Data\\Techno-economic parameters\\fuel_costs.csv",DataFrame)

    for country in countries
        m.ext[:parameters][:technologies][:capacities][country] = Dict()
        m.ext[:parameters][:technologies][:efficiencies][country] = Dict()
        m.ext[:parameters][:technologies][:VOM][country] = Dict()
        m.ext[:parameters][:technologies][:availabilities][country] = Dict()
        m.ext[:parameters][:technologies][:fuel_cost][country] = Dict()
        m.ext[:parameters][:technologies][:emissions][country] = Dict()

        reading_country = reading[reading[!,"Node"] .== country,:]
        for technology in technologies[country]
            #@show(technology)
            capacity = reading_country[reading_country[!,"Generator_ID"] .== technology,:].Value
            #@assert(length(capacity) == 1)
            m.ext[:parameters][:technologies][:capacities][country][technology] = sum(capacity)
            efficiency = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"efficiency"][1]
            availability = 1 - reading_technical[reading_technical[!,"Generator_ID"] .== technology,"Unavailability"][1]
            VOM = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"VOM"][1]
            fuel = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"fuel_type"][1]
            emissions = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"emissions(kg/MWh)"][1]

            if fuel != "None"
                fuel_cost = fuel_prices[fuel_prices.FT .== fuel,string(year)][1]*3.6
            else
                fuel_cost = 0
            end

            m.ext[:parameters][:technologies][:efficiencies][country][technology] = efficiency
            m.ext[:parameters][:technologies][:availabilities][country][technology] = availability
            m.ext[:parameters][:technologies][:VOM][country][technology] = VOM
            m.ext[:parameters][:technologies][:fuel_cost][country][technology] = fuel_cost
            m.ext[:parameters][:technologies][:emissions][country][technology] = emissions

        end
        # for tech in m.ext[:sets][:dispatchable_technologies][country]
        #     efficie
    end
end

function process_line_capacities!(m::Model,scenario::String,year::Int,CY::Int,countries)
    reading_lines = CSV.read("Input Data\\lines.csv",DataFrame)
    reading_lines = reading_lines[reading_lines[!,"Scenario"] .== scenario,:]
    reading_lines = reading_lines[reading_lines[!,"Climate Year"] .== CY,:]
    reading_lines = reading_lines[reading_lines[!,"Year"] .== year,:]

    #Initialize dicts
    for country in countries
        m.ext[:parameters][:connections][country] = Dict()
    end
    # Extract line capacities from data file
    for country in intersect(Set(reading_lines.Node1),m.ext[:sets][:countries])
        reading_country = reading_lines[(reading_lines[!,"Node1"] .== country),:]
        for node_2 in intersect(Set(reading_country.Node2),m.ext[:sets][:countries])
            capacity_imp = reading_country[(reading_country[!,"Node2"] .== node_2).&(reading_country[!,"Parameter"] .== "Import Capacity"),:].Value
            m.ext[:parameters][:connections][country][node_2] = abs.(capacity_imp)
            capacity_exp = reading_country[(reading_country[!,"Node2"] .== node_2).&(reading_country[!,"Parameter"] .== "Export Capacity"),:].Value
            m.ext[:parameters][:connections][node_2][country] = abs.(capacity_exp)
        end
    end
    # Post check on line parameters to fill missing values to 0
    for node1 in keys(m.ext[:sets][:connections])
        #@show(node1)
        for node2 in m.ext[:sets][:connections][node1]
            #print(node2)
            #@assert(!(isempty(m.ext[:parameters][:connections][node1][node2])))
            if isempty(m.ext[:parameters][:connections][node1][node2])
                @show(node1,node2)
                m.ext[:parameters][:connections][node1][node2] = 0
            end
        end
    end
end

function process_hydro_energy_capacities!(m,countries)
    reading_hydro = CSV.read(joinpath("Input Data","hydro_capacities", "energy_caps.csv"),DataFrame)
    hydro_flow_technologies = m.ext[:sets][:hydro_flow_technologies]
    for country in countries
        reading_hydro_country = reading_hydro[reading_hydro[!,"Node"] .== country,:]
        m.ext[:parameters][:technologies][:energy_capacities][country] = Dict()
        if "PS_C" in m.ext[:sets][:storage_technologies][country]
            hydro_energy_storing_techs = vcat(hydro_flow_technologies[country], "PS_C")
        else
            hydro_energy_storing_techs = hydro_flow_technologies[country]
        end
        for hydro_tech in hydro_energy_storing_techs
            capacity = reading_hydro_country[!,hydro_tech]
            if length(capacity ) == 1
                m.ext[:parameters][:technologies][:energy_capacities][country][hydro_tech] = capacity[1]
            elseif length(capacity ) == 0
                print(country)
                print(hydro_tech)
                m.ext[:parameters][:technologies][:energy_capacities][country][hydro_tech]  = 0
            else
                #throw error
                @assert(length(capacity ) == 1)
            end
        end
    end
end

function process_battery_energy_capacities!(m,countries)
    for country in countries
        if "Battery" in m.ext[:sets][:technologies][country]
            m.ext[:parameters][:technologies][:energy_capacities][country]["Battery"] = 3*m.ext[:parameters][:technologies][:capacities][country]["Battery"]
        end
    end
end

function process_DSR_capacities(m,countries,scenario,CY)
    reading = CSV.read("Input Data\\gen_cap.csv",DataFrame)
    reading = reading[reading[!,"Scenario"] .== scenario,:]
    reading = reading[reading[!,"Year"] .== year,:]
    reading = reading[reading[!,"Climate Year"] .== CY,:]
    for country in countries
        reading_country = reading[reading[!,"Node"] .== country,:]
        capacity = reading_country[reading_country[!,"Generator_ID"] .== "DSR",:].Value
        if length(capacity) == 1
            m.ext[:parameters][:DSR][:capacities][country] = capacity[1]
            m.ext[:parameters][:DSR][:horizons][country] = 3
        elseif length(capacity) == 0
            m.ext[:parameters][:DSR][:capacities][country] = 0
            m.ext[:parameters][:DSR][:horizons][country] = 3
        else
            @show("DSR capacity not uniquely defined for $country")
        end
    end
end

function process_flat_generation(m,countries,scenario,CY)
    reading = CSV.read("Input Data\\gen_prod.csv",DataFrame)
    reading = reading[reading[!,"Scenario"] .== scenario,:]
    reading = reading[reading[!,"Year"] .== year,:]
    reading = reading[reading[!,"Climate Year"] .== CY,:]
    for country in countries
        m.ext[:parameters][:technologies][:total_gen][country] = Dict()
        reading_country = reading[reading[!,"Node"] .== country,:]
        for tech in m.ext[:sets][:flat_run_technologies][country]
            generation = reading_country[reading_country[!,"Generator_ID"] .== tech,:].Value
            m.ext[:parameters][:technologies][:total_gen][country][tech] = sum(generation)
        end
    end
end
##
function process_time_series!(m::Model,scenario::String,year,CY)
    countries = m.ext[:sets][:countries]

    m.ext[:timeseries] = Dict()
    m.ext[:timeseries][:demand] = Dict()
    m.ext[:timeseries][:inter_gen] = Dict()

    process_demand_time_series!(m,scenario,countries,year,CY)
    process_intermittent_time_series!(m,countries,CY)
    process_hydro_inflow_time_series!(m,countries,CY)
end

# function process_demand_time_series!(m::Model, scenario::String,countries,year)
#     scenario_dict = Dict("Distributed Energy" => "DE","Global Ambition" => "GA","National Trends" => "NT")
#     filename = string(scenario_dict[scenario],"2040_Demand_CY1984.csv")
#     demand_reading = CSV.read(joinpath("Input Data",filename),DataFrame)
#     for country in countries
#         m.ext[:timeseries][:demand][country] = demand_reading[!,country]
#     end
# end

function process_demand_time_series!(m::Model, scenario::String,countries,year,CY)
    scenario_dict = Dict("Distributed Energy" => "DistributedEnergy","Global Ambition" => "GlobalAmbition","National Trends" => "NationalTrends")
    filename = string("Demand_$(year)_$(scenario_dict[scenario])_$(CY).csv")
    demand_reading = CSV.read(joinpath("Input Data","time_series_output",filename),DataFrame)
    l = 8760
    for country in countries
        if !(country in(["DKKF" "LUV1" "DEKF"]))
            m.ext[:timeseries][:demand][country] = demand_reading[!,country]
            l = length(m.ext[:timeseries][:demand][country])
        else
            m.ext[:timeseries][:demand][country] = zeros(l)
        end
    end
end

function process_intermittent_time_series!(m::Model, countries)
    for country in countries
        if !(isempty(m.ext[:sets][:intermittent_technologies][country]))
            m.ext[:timeseries][:inter_gen][country] = Dict(im_t => [] for im_t in m.ext[:sets][:intermittent_technologies][country])
        end
    end

    im_techs = Dict("PV" => "pv","w_on" => "onshore","w_off" => "offshore")
    for im_t in keys(im_techs)
        # print(im_t)
        tech_reading = CSV.read(joinpath("Input Data","time_series_output",string(im_techs[im_t],".csv")),DataFrame)
        for country in countries
            if country =="BE00"
                print(keys(m.ext[:sets][:intermittent_technologies][country]))
            end
            if im_t in m.ext[:sets][:intermittent_technologies][country]
                m.ext[:timeseries][:inter_gen][country][im_t] = tech_reading[!,country]
            end
        end
    end
end

function process_intermittent_time_series!(m::Model, countries,CY)
    for country in countries
        if !(isempty(m.ext[:sets][:intermittent_technologies][country]))
            m.ext[:timeseries][:inter_gen][country] = Dict(im_t => [] for im_t in m.ext[:sets][:intermittent_technologies][country])
        end
    end

    im_techs = Dict("PV" => "pv","w_on" => "onshore","w_off" => "offshore")
    for im_t in keys(im_techs)
        # print(im_t)
        tech_reading = CSV.read(joinpath("Input Data","time_series_output",string(im_techs[im_t],"_$CY",".csv")),DataFrame)
        for country in countries
            if country =="BE00"
                print(keys(m.ext[:sets][:intermittent_technologies][country]))
            end
            if im_t in m.ext[:sets][:intermittent_technologies][country]
                m.ext[:timeseries][:inter_gen][country][im_t] = tech_reading[!,country]
            end
        end
    end
end

function process_hydro_inflow_time_series!(m::Model,countries)
    m.ext[:timeseries][:hydro_inflow] = Dict()
    for country in countries
        if !(isempty(m.ext[:sets][:hydro_flow_technologies][country]))
            m.ext[:timeseries][:hydro_inflow][country] = Dict(hyd_t => [] for hyd_t in m.ext[:sets][:hydro_flow_technologies][country])
        end
    end
    hydro_inflow_techs = Dict("PS_O" => "PS_O","ROR" => "ROR","RES" => "RES")
    for hydro_inflow_tech in keys(hydro_inflow_techs)
        #print(im_t)
        tech_reading = CSV.read(joinpath("Input Data","time_series_output",string(hydro_inflow_techs[hydro_inflow_tech],".csv")),DataFrame)
        for country in countries
            if hydro_inflow_tech in m.ext[:sets][:hydro_flow_technologies][country]
                if country != "FR15"
                    m.ext[:timeseries][:hydro_inflow][country][hydro_inflow_tech] = tech_reading[!,country]
                else
                    m.ext[:timeseries][:hydro_inflow][country][hydro_inflow_tech] = zeros(8760)
                end
            end
        end
    end
end

function process_hydro_inflow_time_series!(m::Model,countries,CY)
    m.ext[:timeseries][:hydro_inflow] = Dict()
    for country in countries
        if !(isempty(m.ext[:sets][:hydro_flow_technologies][country]))
            m.ext[:timeseries][:hydro_inflow][country] = Dict(hyd_t => [] for hyd_t in m.ext[:sets][:hydro_flow_technologies][country])
        end
    end
    hydro_inflow_techs = Dict("PS_O" => "PS_O","ROR" => "ROR","RES" => "RES")
    for hydro_inflow_tech in keys(hydro_inflow_techs)
        #print(im_t)
        tech_reading = CSV.read(joinpath("Input Data","time_series_output",string(hydro_inflow_techs[hydro_inflow_tech],"_$CY",".csv")),DataFrame)
        for country in countries
            if hydro_inflow_tech in m.ext[:sets][:hydro_flow_technologies][country]
                if country != "FR15"
                    m.ext[:timeseries][:hydro_inflow][country][hydro_inflow_tech] = tech_reading[!,country]
                else
                    m.ext[:timeseries][:hydro_inflow][country][hydro_inflow_tech] = zeros(8760)
                end
            end
        end
    end
end
##
function remove_capacity_country(m::Model,country::String)
    m.ext[:parameters][:DSR][:capacities][country] = 0
    for technology in m.ext[:sets][:technologies][country]
        print(technology)
        m.ext[:parameters][:technologies][:capacities][country][technology] = 0
    end
    for technology in m.ext[:sets][:flat_run_technologies][country]
        m.ext[:parameters][:technologies][:total_gen][country][technology] = 0
    end
end

function remove_capacity_country(m::Model,country::String)
    m.ext[:parameters][:DSR][:capacities][country] = 0
    for technology in m.ext[:sets][:technologies][country]
        print(technology)
        m.ext[:parameters][:technologies][:capacities][country][technology] = 0
    end
    for technology in m.ext[:sets][:flat_run_technologies][country]
        m.ext[:parameters][:technologies][:total_gen][country][technology] = 0
    end
end

function set_demand_country(m::Model,country::String,demand::Int)
    m.ext[:timeseries][:demand][country] .= demand
end
##
function update_technologies_past_2040(m:: Model, year::Int)
    if year == 2045
        fraction = 0.5
        update_technology_sets_and_capacities(m,fraction)
    elseif year == 2050
        fraction = 1
        update_technology_sets_and_capacities(m,fraction)
    end
    update_fuel_prices_and_emissions(m,year)
    process_co2_price(m,year)
end
function update_technology_sets_and_capacities(m::Model,fraction)
    mapping = Dict("CCGT" => "CCGT_H2","OCGT" => "OCGT_H2","Coal" => "Coal_bio")
    for country in m.ext[:sets][:countries]
        for old_tech in keys(mapping)
            if old_tech in m.ext[:sets][:technologies][country]
                cap_old = m.ext[:parameters][:technologies][:capacities][country][old_tech]
                new_tech = mapping[old_tech]
                if !(new_tech in m.ext[:sets][:technologies][country])
                    append!(m.ext[:sets][:technologies][country],[new_tech])
                    append!(m.ext[:sets][:dispatchable_technologies][country],[new_tech])
                    m.ext[:parameters][:technologies][:capacities][country][new_tech] = fraction * cap_old
                    m.ext[:parameters][:technologies][:capacities][country][old_tech] = (1-fraction) * cap_old
                else
                    m.ext[:parameters][:technologies][:capacities][country][new_tech] += fraction * cap_old
                    m.ext[:parameters][:technologies][:capacities][country][old_tech] = (1-fraction) * cap_old
                end
            end
        end
    end
end
function update_fuel_prices_and_emissions(m,year)
    reading_technical = CSV.read("Input Data\\Techno-economic parameters\\Generator_efficiencies.csv",DataFrame)
    fuel_prices = CSV.read("Input Data\\Techno-economic parameters\\fuel_costs.csv",DataFrame)

    for country in m.ext[:sets][:countries]
        for technology in m.ext[:sets][:technologies][country]
            #println(technology)
            fuel = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"fuel_type"][1]
            emissions = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"emissions(kg/MWh)"][1]
            efficiency = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"efficiency"][1]
            VOM = reading_technical[reading_technical[!,"Generator_ID"] .== technology,"VOM"][1]

            if fuel != "None"
                fuel_cost = fuel_prices[fuel_prices.FT .== fuel,string(year)][1]*3.6
            else
                fuel_cost = 0
            end
            m.ext[:parameters][:technologies][:fuel_cost][country][technology] = fuel_cost
            m.ext[:parameters][:technologies][:emissions][country][technology] = emissions
            m.ext[:parameters][:technologies][:efficiencies][country][technology] = efficiency
            m.ext[:parameters][:technologies][:VOM][country][technology] = VOM

        end
    end
end

##
function build_base_model!(m::Model,endtime,VOLL)
    CO2_price = m.ext[:parameters][:CO2_price]
    countries =  m.ext[:sets][:countries]
    timesteps = collect(1:endtime)

    technologies = m.ext[:sets][:technologies]
    dispatchable_technologies = m.ext[:sets][:dispatchable_technologies]
    flat_run_technologies = m.ext[:sets][:flat_run_technologies]

    intermittent_technologies = m.ext[:sets][:intermittent_technologies]
    storage_technologies = m.ext[:sets][:storage_technologies]

    soc_technologies = m.ext[:sets][:soc_technologies]
    hydro_flow_technologies_without_pumping = m.ext[:sets][:hydro_flow_technologies_without_pumping]
    hydro_flow_technologies_with_pumping = m.ext[:sets][:hydro_flow_technologies_with_pumping]

    pure_storage_technologies = m.ext[:sets][:pure_storage_technologies]


    capacities = m.ext[:parameters][:technologies][:capacities]
    total_gen = m.ext[:parameters][:technologies][:total_gen]

    efficiencies = m.ext[:parameters][:technologies][:efficiencies]
    VOM = m.ext[:parameters][:technologies][:VOM]
    availability = m.ext[:parameters][:technologies][:availabilities]
    fuel_cost = m.ext[:parameters][:technologies][:fuel_cost]
    emissions = m.ext[:parameters][:technologies][:emissions]

    demand = m.ext[:timeseries][:demand]
    intermittent_timeseries = m.ext[:timeseries][:inter_gen]
    hydro_flow = m.ext[:timeseries][:hydro_inflow]

    ###################
    #Variables
    ###################

    m.ext[:variables] = Dict()
    production = m.ext[:variables][:production] = @variable(m,[c= countries, tech=technologies[c],time=timesteps],base_name = "production")
    load_shedding =  m.ext[:variables][:load_shedding] = @variable(m,[c= countries,time=timesteps],base_name = "load_shedding")
    curtailment = m.ext[:variables][:curtailment] = @variable(m,[c= countries,time=timesteps], base_name = "curtailment")

    soc = m.ext[:variables][:soc] = @variable(m,[c= countries,tech = soc_technologies[c],time=timesteps],base_name = "State_of_charge")
    charge = m.ext[:variables][:charge] = @variable(m,[c= countries,tech = storage_technologies[c] ,time=timesteps],base_name = "charge")
    water_dumping = m.ext[:variables][:water_dumping] = @variable(m,[c= countries,tech = hydro_flow_technologies_without_pumping[c] ,time=timesteps],base_name = "water_dumping")

    #Technology production used as discharge
    #discharge = m.ext[:variables][:discharge] = @variable(m,[c= countries,tech = storage_technologies ,time=timesteps],base_name = "discharge")

    #############
    #Expressions
    #############
    m.ext[:expressions] = Dict()

    total_production_timestep = m.ext[:expressions][:total_production_timestep] =
    @expression(m, [c = countries, time = timesteps],
    sum(production[c,tech,time] for tech in technologies[c])
    )
    renewable_production = m.ext[:expressions][:renewable_production] =
    @expression(m, [c = countries, time = timesteps],
    sum(production[c,ren_tech,time] for ren_tech in m.ext[:sets][:intermittent_technologies][c])
    )

    production_cost = m.ext[:expressions][:production_cost] =
    @expression(m, [c = countries, time = timesteps],
    sum(production[c,tech,time]*VOM[c][tech] for tech in technologies[c])
    + sum(production[c,tech,time]*(1/efficiencies[c][tech])*fuel_cost[c][tech] for tech in dispatchable_technologies[c])
    + sum(production[c,tech,time]*(1/efficiencies[c][tech])*emissions[c][tech]*CO2_price for tech in dispatchable_technologies[c])
    )
    VOM_cost = m.ext[:expressions][:VOM_cost] =
    @expression(m, [c = countries, tech = technologies[c], time = timesteps],
    production[c,tech,time]*VOM[c][tech]
    )
    fuel_cost = m.ext[:expressions][:fuel_cost] =
    @expression(m, [c = countries, tech = dispatchable_technologies[c], time = timesteps],
    production[c,tech,time]*(1/efficiencies[c][tech])*fuel_cost[c][tech]
    )
    C02_cost = m.ext[:expressions][:CO2_cost] =
    @expression(m, [c = countries, tech = dispatchable_technologies[c], time = timesteps],
    production[c,tech,time]*(1/efficiencies[c][tech])*emissions[c][tech]*CO2_price
    )

    load_shedding_cost = m.ext[:expressions][:load_shedding_cost] =
    @expression(m, [c = countries, time = timesteps],
    load_shedding[c,time]*VOLL
    )

    #############
    #Constraints
    #############

    m.ext[:constraints] = Dict()

    #Production must be positive and respect the installed capacity for all technologies
    m.ext[:constraints][:production_capacity] = @constraint(m,[c = countries, tech = technologies[c],time = timesteps],
    0<=production[c,tech,time] <=  capacities[c][tech]
    )
    #Production of flat run technologies
    m.ext[:constraints][:production_flat_runs] = @constraint(m,[c = countries, tech = flat_run_technologies[c],time = timesteps],
    production[c,tech,time] <=  total_gen[c][tech]/8760*1000
    )
    #Load shedding must at all times be positive
    m.ext[:constraints][:load_shedding_pos] = @constraint(m,[c = countries, tech = technologies[c],time = timesteps],
    0<=load_shedding[c,time]
    )
    #Curtailment must at all times be positive
    m.ext[:constraints][:curtailment_pos] = @constraint(m,[c = countries,time = timesteps],
    0<=curtailment[c,time]
    )
    #Curtailment must at all times be smaller than renewable production
    m.ext[:constraints][:curtailment_max] = @constraint(m,[c = countries,time = timesteps],
    curtailment[c,time]<= renewable_production[c,time]
    )

    #Charging must at all times be positive
    m.ext[:constraints][:charge_pos] = @constraint(m,[c = countries,tech=storage_technologies[c],time = timesteps],
    0<=charge[c,tech,time]
    )
    #Water dumping must at all times be positive
    m.ext[:constraints][:charge_pos] = @constraint(m,[c = countries,tech=hydro_flow_technologies_without_pumping[c],time = timesteps],
    0<=water_dumping[c,tech,time]
    )
    #For the intermittent renewable sources, production is governed by the product of capacity factors and installed capacities
    m.ext[:constraints][:intermittent_production] = @constraint(m,[c = countries, tech = intermittent_technologies[c],time = timesteps],
    production[c,tech,time] ==  capacities[c][tech]*intermittent_timeseries[c][tech][time]
    )
    #State of charge of all energy storing technologies is limited by the energy capacity
    m.ext[:constraints][:soc_limit] = @constraint(m,[c = countries, tech = soc_technologies[c],time = timesteps],
    0<=soc[c,tech,time] <= m.ext[:parameters][:technologies][:energy_capacities][c][tech]
    )
    m.ext[:constraints][:soc_boundaries] = @constraint(m,[c = countries, tech = soc_technologies[c]],
    soc[c,tech,1] == soc[c,tech,endtime]
    )
    # State of charge of all pure storage technologies is updated based on charging and discharging (= production)
    m.ext[:constraints][:soc_evolution_pure] = @constraint(m,[c = countries, tech = pure_storage_technologies[c],time = timesteps[2:end]],
    soc[c,tech,time] ==  soc[c,tech,time-1] + charge[c,tech,time-1] * efficiencies[c][tech]
    -  production[c,tech,time-1] * (1/efficiencies[c][tech])
    )
    # State of charge of hydro inflow technologies is updated based on inflow timeseries and production
    m.ext[:constraints][:soc_evolution_inflow] = @constraint(m,[c = countries, tech = hydro_flow_technologies_without_pumping[c],time = timesteps[2:end]],
    soc[c,tech,time] ==  soc[c,tech,time-1] + hydro_flow[c][tech][time-1] * (1/efficiencies[c][tech]) -water_dumping[c,tech,time] * efficiencies[c][tech]
    -  production[c,tech,time-1] * (1/efficiencies[c][tech])
    )
    #State of charge of pumped hydro technologies with inflow is updated based inflow timeseries, production, and pumping
    m.ext[:constraints][:soc_evolution_inflow_pumped] = @constraint(m,[c = countries, tech = hydro_flow_technologies_with_pumping[c],time = timesteps[2:end]],
    soc[c,tech,time] ==  soc[c,tech,time-1] + hydro_flow[c][tech][time-1] * (1/efficiencies[c][tech]) + charge[c,tech,time] * efficiencies[c][tech]
    -  production[c,tech,time-1] * (1/efficiencies[c][tech])
    )
end

function build_isolated_model_2!(m::Model,endtime,VOLL,CO2_price)

    build_base_model!(m,endtime,VOLL,CO2_price)

    countries = m.ext[:sets][:countries]
    timesteps = 1:endtime
    total_production_timestep = m.ext[:expressions][:total_production_timestep]
    load_shedding = m.ext[:variables][:load_shedding]
    curtailment = m.ext[:variables][:curtailment]
    charge = m.ext[:variables][:charge]
    storage_technologies = m.ext[:sets][:storage_technologies]

    VOM_cost = m.ext[:expressions][:VOM_cost]
    fuel_cost = m.ext[:expressions][:fuel_cost]
    load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
    CO2_cost = m.ext[:expressions][:CO2_cost]

    demand = m.ext[:timeseries][:demand]
    # Demand met for all timesteps
    m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
        total_production_timestep[c,time] + load_shedding[c,time] - curtailment[c,time]  == demand[c][time] + sum(charge[c,tech,time] for tech in storage_technologies[c])
    )
    m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost))
end

function build_isolated_model_DSR!(m::Model,endtime,VOLL,CO2_price,DSR_price)

    build_base_model!(m,endtime,VOLL,CO2_price)

    countries = m.ext[:sets][:countries]
    dsr_capacities = m.ext[:parameters][:DSR][:capacities]

    timesteps = 1:endtime
    total_production_timestep = m.ext[:expressions][:total_production_timestep]
    load_shedding = m.ext[:variables][:load_shedding]
    curtailment = m.ext[:variables][:curtailment]
    charge = m.ext[:variables][:charge]
    storage_technologies = m.ext[:sets][:storage_technologies]

    VOM_cost = m.ext[:expressions][:VOM_cost]
    fuel_cost = m.ext[:expressions][:fuel_cost]
    load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
    CO2_cost = m.ext[:expressions][:CO2_cost]


    DSR = m.ext[:variables][:DSR] = @variable(m, [c = countries, t = timesteps],base_name = "DSR")
    DSR_cost = m.ext[:expressions][:DSR_cost] = @expression(m,[c = countries, t = timesteps],
    DSR[c,t] * DSR_price
    )
    m.ext[:constraints][:DSR_pos] = @constraint(m, [c = countries, t = timesteps],
    0<= DSR[c,t] <= dsr_capacities[c] )
    # m.ext[:constraints][:DSR_pos] = @constraint(m, [c = countries, t = timesteps],
    # DSR[c,t] <= dsr_capacities[c] )


    demand = m.ext[:timeseries][:demand]
    # Demand met for all timesteps
    m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
        total_production_timestep[c,time] + load_shedding[c,time] + DSR[c,time] - curtailment[c,time]  == demand[c][time] + sum(charge[c,tech,time] for tech in storage_technologies[c])
    )
    m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(DSR_cost))
end

function build_isolated_model_DSR_shift!(m::Model,endtime,VOLL,CO2_price,DSR_price)

    build_base_model!(m,endtime,VOLL,CO2_price)

    countries = m.ext[:sets][:countries]
    dsr_capacities = m.ext[:parameters][:DSR][:capacities]
    dsr_horizons = m.ext[:parameters][:DSR][:horizons]

    timesteps = 1:endtime
    total_production_timestep = m.ext[:expressions][:total_production_timestep]
    load_shedding = m.ext[:variables][:load_shedding]
    curtailment = m.ext[:variables][:curtailment]
    charge = m.ext[:variables][:charge]
    storage_technologies = m.ext[:sets][:storage_technologies]

    VOM_cost = m.ext[:expressions][:VOM_cost]
    fuel_cost = m.ext[:expressions][:fuel_cost]
    load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
    CO2_cost = m.ext[:expressions][:CO2_cost]



    DSR_up = m.ext[:variables][:DSR_up] = @variable(m, [c = countries, t = timesteps],lower_bound = 0,base_name = "DSR_up")
    DSR_down = m.ext[:variables][:DSR_down] = @variable(m, [c = countries, t = timesteps,shift_from = t-dsr_horizons[c]:t+dsr_horizons[c] ],lower_bound = 0,base_name = "DSR_down")



    DSR_cost = m.ext[:expressions][:DSR_cost] = @expression(m,[c = countries, t = timesteps],
    DSR_up[c,t] * DSR_price
    )
    # m.ext[:constraints][:DSR_shed_limits] = @constraint(m, [c = countries, t = timesteps],
    # 0<= DSR_shed[c,t] <= dsr_capacities[c]/4 )

    m.ext[:constraints][:DSR_up_limits] = @constraint(m, [c = countries, t = timesteps],
    DSR_up[c,t] <= dsr_capacities[c] )

    m.ext[:constraints][:DSR_down_limits] = @constraint(m, [c = countries, t = timesteps],
    sum(DSR_down[c,t,shift_from] for shift_from in t-dsr_horizons[c]:t+dsr_horizons[c] if (1<=shift_from<=endtime)) <= dsr_capacities[c] )

    m.ext[:constraints][:DSR_balance] = @constraint(m, [c = countries, shift_from = timesteps],
    sum(DSR_down[c,shift_to,shift_from] for shift_to in shift_from-dsr_horizons[c]:shift_from+dsr_horizons[c] if (1<=shift_to<=endtime)) == DSR_up[c,shift_from] )

    demand = m.ext[:timeseries][:demand]
    # Demand met for all timesteps
    m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
        total_production_timestep[c,time] + load_shedding[c,time]  - curtailment[c,time]  == demand[c][time] + DSR_up[c,time] - sum(DSR_down[c,time,shift_from] for shift_from in time-dsr_horizons[c]:time+dsr_horizons[c] if (1<=shift_from<=endtime))  + sum(charge[c,tech,time] for tech in storage_technologies[c])
    )
    m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(DSR_cost))
end

function build_NTC_model!(m:: Model,endtime,VOLL,transport_cost)

        build_base_model!(m,endtime,VOLL)

        countries = m.ext[:sets][:countries]
        timesteps = collect(1:endtime)
        connections = m.ext[:sets][:connections]
        storage_technologies = m.ext[:sets][:storage_technologies]
        #And extract relevant parameters

        transfer_capacities = m.ext[:parameters][:connections]

        demand = m.ext[:timeseries][:demand]

        total_production_timestep = m.ext[:expressions][:total_production_timestep]
        curtailment = m.ext[:variables][:curtailment]
        load_shedding = m.ext[:variables][:load_shedding]
        charge = m.ext[:variables][:charge]


        el_import = m.ext[:variables][:import] = @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "import")
        el_export = m.ext[:variables][:export]=  @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "export")

        m.ext[:constraints][:import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
            maximum(transfer_capacities[c][neighbor]) >= el_import[c,neighbor,time] >= 0
        )
        # m.ext[:constraints][:export] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
        #     maximum(transfer_capacities[c][neighbor]) >= el_export[c,neighbor,time] >= 0
        # )

        m.ext[:constraints][:export_import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
            el_export[c,neighbor,time] == el_import[neighbor,c,time]
        )

        m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
            total_production_timestep[c,time] + load_shedding[c,time] - curtailment[c,time] + sum(el_import[c,nb,time] for nb in connections[c])  == demand[c][time] + sum(el_export[c,nb,time] for nb in connections[c])  + sum(charge[c,tech,time] for tech in storage_technologies[c])
        )
        VOM_cost = m.ext[:expressions][:VOM_cost]
        fuel_cost = m.ext[:expressions][:fuel_cost]
        load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
        CO2_cost = m.ext[:expressions][:CO2_cost]
        transport_cost =m.ext[:expressions][:transport_cost]= el_import*transport_cost
        m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(transport_cost))
end
function build_NTC_model_DSR!(m:: Model,endtime,VOLL,DSR_price,transport_cost)

        build_base_model!(m,endtime,VOLL)

        countries = m.ext[:sets][:countries]
        dsr_capacities = m.ext[:parameters][:DSR][:capacities]

        timesteps = collect(1:endtime)
        connections = m.ext[:sets][:connections]
        storage_technologies = m.ext[:sets][:storage_technologies]
        #And extract relevant parameters

        transfer_capacities = m.ext[:parameters][:connections]

        demand = m.ext[:timeseries][:demand]

        total_production_timestep = m.ext[:expressions][:total_production_timestep]
        curtailment = m.ext[:variables][:curtailment]
        load_shedding = m.ext[:variables][:load_shedding]
        charge = m.ext[:variables][:charge]


        el_import = m.ext[:variables][:import] = @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "import")
        el_export = m.ext[:variables][:export]=  @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "export")

        DSR = m.ext[:variables][:DSR] = @variable(m, [c = countries, t = timesteps],base_name = "DSR")
        DSR_cost = m.ext[:expressions][:DSR_cost] = @expression(m,[c = countries, t = timesteps],
        DSR[c,t] * DSR_price
        )
        m.ext[:constraints][:DSR_pos] = @constraint(m, [c = countries, t = timesteps],
        0<= DSR[c,t] <= dsr_capacities[c] )


        m.ext[:constraints][:import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
            maximum(transfer_capacities[c][neighbor]) >= el_import[c,neighbor,time] >= 0
        )
        # m.ext[:constraints][:export] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
        #     maximum(transfer_capacities[c][neighbor]) >= el_export[c,neighbor,time] >= 0
        # )

        m.ext[:constraints][:export_import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
            el_export[c,neighbor,time] == el_import[neighbor,c,time]
        )

        m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
            total_production_timestep[c,time] + load_shedding[c,time] + DSR[c,time] - curtailment[c,time] + sum(el_import[c,nb,time] for nb in connections[c])  == demand[c][time] + sum(el_export[c,nb,time] for nb in connections[c])  + sum(charge[c,tech,time] for tech in storage_technologies[c])
        )
        VOM_cost = m.ext[:expressions][:VOM_cost]
        fuel_cost = m.ext[:expressions][:fuel_cost]
        load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
        CO2_cost = m.ext[:expressions][:CO2_cost]
        transport_cost =m.ext[:expressions][:transport_cost]= el_import*transport_cost
        m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(transport_cost) + sum(DSR_cost))
end

function build_NTC_model_DSR_shift!(m:: Model,endtime,VOLL,CO2_price,DSR_shift_price,sheddable_fraction,DSR_shed_price)
    build_base_model!(m::Model,endtime,VOLL,CO2_price)

    countries = m.ext[:sets][:countries]
    dsr_capacities = m.ext[:parameters][:DSR][:capacities]
    dsr_horizons = m.ext[:parameters][:DSR][:horizons]
    timesteps = collect(1:endtime)
    connections = m.ext[:sets][:connections]
    storage_technologies = m.ext[:sets][:storage_technologies]

    transfer_capacities = m.ext[:parameters][:connections]

    demand = m.ext[:timeseries][:demand]

    total_production_timestep = m.ext[:expressions][:total_production_timestep]

    curtailment = m.ext[:variables][:curtailment]
    load_shedding = m.ext[:variables][:load_shedding]
    charge = m.ext[:variables][:charge]


    el_import = m.ext[:variables][:import] = @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "import")
    el_export = m.ext[:variables][:export]=  @variable(m,[c = countries, neighbor = connections[c] ,time = timesteps], base_name = "export")

    m.ext[:constraints][:import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
        maximum(transfer_capacities[c][neighbor]) >= el_import[c,neighbor,time] >= 0
    )

    m.ext[:constraints][:export_import] = @constraint(m,[c = countries, neighbor = connections[c] ,time = timesteps],
        el_export[c,neighbor,time] == el_import[neighbor,c,time]
    )

    DSR_up = m.ext[:variables][:DSR_up] = @variable(m, [c = countries, t = timesteps],lower_bound = 0,base_name = "DSR_up")
    DSR_down = m.ext[:variables][:DSR_down] = @variable(m, [c = countries, t = timesteps,shift_from = t-dsr_horizons[c]:t+dsr_horizons[c] ],lower_bound = 0,base_name = "DSR_down")
    DSR_shed = m.ext[:variables][:DSR_shed] = @variable(m, [c = countries, t = timesteps],lower_bound = 0,base_name = "DSR_shed")

    m.ext[:constraints][:DSR_shed_limits] = @constraint(m, [c = countries, t = timesteps],
    DSR_shed[c,t] <= dsr_capacities[c]*sheddable_fraction)

    m.ext[:constraints][:DSR_up_limits] = @constraint(m, [c = countries, t = timesteps],
    DSR_up[c,t] <= dsr_capacities[c])

    m.ext[:constraints][:DSR_down_limits] = @constraint(m, [c = countries, t = timesteps],
    sum(DSR_down[c,t,shift_from] for shift_from in t-dsr_horizons[c]:t+dsr_horizons[c] if (1<=shift_from<=endtime)) + DSR_shed[c,t] <=  dsr_capacities[c] )

    m.ext[:constraints][:DSR_balance] = @constraint(m, [c = countries, shift_from = timesteps],
    sum(DSR_down[c,shift_to,shift_from] for shift_to in shift_from-dsr_horizons[c]:shift_from+dsr_horizons[c] if (1<=shift_to<=endtime)) == DSR_up[c,shift_from] )

    # Demand met for all timesteps
    m.ext[:constraints][:demand_met] = @constraint(m,demand_met[c = countries, time = timesteps],
        total_production_timestep[c,time]
        + load_shedding[c,time]
        + DSR_shed[c,time]
        - curtailment[c,time]
        + sum(el_import[c,nb,time] for nb in connections[c])
        - demand[c][time]
        - sum(el_export[c,nb,time] for nb in connections[c])
        - DSR_up[c,time]
        + sum(DSR_down[c,time,shift_from] for shift_from in time-dsr_horizons[c]:time+dsr_horizons[c] if (1<=shift_from<=endtime))
        - sum(charge[c,tech,time] for tech in storage_technologies[c])
        == 0
    )

    VOM_cost = m.ext[:expressions][:VOM_cost]
    fuel_cost = m.ext[:expressions][:fuel_cost]
    load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
    CO2_cost = m.ext[:expressions][:CO2_cost]
    transport_cost =m.ext[:expressions][:transport_cost]= el_import*0.1
    DSR_cost = m.ext[:expressions][:DSR_shift_cost] = @expression(m,[c = countries, t = timesteps],
    DSR_up[c,t] * DSR_shift_price
    )

    DSR_shed_cost = m.ext[:expressions][:DSR_shed_cost] = @expression(m,[c = countries, t = timesteps],
    DSR_shed[c,t] * DSR_shed_price
    )
    m.ext[:objective] = @objective(m,Min, sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(DSR_cost) + sum(transport_cost) + sum(DSR_shed_cost))
end

function fix_soc_decisions(m::Model,soc_given,production_given,timesteps,country)
    countries = filter!(e->e !=country,m.ext[:sets][:countries] )
    soc_technologies = m.ext[:sets][:soc_technologies]
    soc = m.ext[:variables][:soc]
    production = m.ext[:variables][:production]
    m.ext[:constraints][:soc_fixed] = @constraint(m,[c = countries, tech = soc_technologies[c] ,time = timesteps],
        soc[c,tech,time] == soc_given[c,tech,time]
    )
    m.ext[:constraints][:soc_production_fixe] = @constraint(m,[c = countries, tech = soc_technologies[c] ,time = timesteps],
        production[c,tech,time] == production_given[c,tech,time]
    )
end

function fix_soc_decisions_from_dict(m::Model,soc_given,production_given,timesteps,country)
    countries = filter!(e->e !=country,m.ext[:sets][:countries] )
    soc_technologies = m.ext[:sets][:soc_technologies]
    storage_technologies = m.ext[:sets][:storage_technologies]

    soc = m.ext[:variables][:soc]
    production = m.ext[:variables][:production]
    charge = m.ext[:variables][:charge]
    m.ext[:constraints][:soc_fixed] = @constraint(m,[c = countries, tech = soc_technologies[c] ,time = timesteps],
        soc[c,tech,time] == soc_given[(c,tech,time)]
    )
    m.ext[:constraints][:soc_production_fixe] = @constraint(m,[c = countries, tech = soc_technologies[c] ,time = timesteps],
        production[c,tech,time] == production_given[(c,tech,time)]
    )
    m.ext[:constraints][:charge_zero] = @constraint(m,[tech = storage_technologies[country] ,time = timesteps],
        charge[country,tech,time] == 0
    )
end
function fix_DSR_decisions(m::Model,DSR_up_given,DSR_down_given,timesteps,country)
    countries = filter!(e->e !=country,m.ext[:sets][:countries] )
    DSR_up = m.ext[:variables][:DSR_up]
    DSR_down = m.ext[:variables][:DSR_down]
    dsr_horizons = m.ext[:parameters][:DSR][:horizons]
    m.ext[:constraints][:DSR_up_fixed] = @constraint(m,[c = countries,time = timesteps],
        DSR_up[c,time] == DSR_up_given[c,time]
    )
    m.ext[:constraints][:DSR_down_fixed] = @constraint(m,[c = countries ,time = timesteps,t_from = time-dsr_horizons[c]:time+dsr_horizons[c]],
        DSR_down[c,time,t_from] == DSR_down_given[c,time,t_from]
    )
end
