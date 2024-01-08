include("model_builder.jl")
include("curve_based_model_builder.jl")

function full_build_and_optimize_investment_model(m::Model ; global_param_dict:: Dict)
    endtime = global_param_dict["endtime"]
    CY = global_param_dict["Climate_year"]
    CY_ts = global_param_dict["Climate_year_ts"]
    VOLL = global_param_dict["ValOfLostLoad"]
    transp_cost = global_param_dict["transport_cost"]
    country = global_param_dict["country"]
    scenario = global_param_dict["scenario"]
    year = global_param_dict["year"]
    type = global_param_dict["type"]
    define_sets!(m,scenario,year,CY,[],[country])
    if type == "isolated"
        build_isolated!(m,endtime,scenario,year,CY,CY_ts,country,VOLL)
    elseif type == "NTC"
        build_NTC!(m,endtime,scenario,year,CY,CY_ts,country,VOLL,transp_cost)
    elseif type =="TradeCurves"
        build_with_trade_curves!(m,endtime,scenario,year,CY,CY_ts,country,VOLL,transp_cost)
    end
    optimize!(m)
    # print("Belgium isolated = ",isolated, JuMP.value.(m.ext[:variables][:invested_cap]))
    peak_dem = maximum(m.ext[:timeseries][:demand][country][1:endtime])

    demand = sum(m.ext[:timeseries][:demand][country][1:endtime])
    if type == "isolated" 
        imported = 0
        exported = 0
    elseif type == "TradeCurves"
        # imported = sum([sum(JuMP.value.(m.ext[:variables][:import][country,neighbor,t]
        #     for neighbor in m.ext[:sets][:connections][country])) for t in 1:endtime])
        # exported = sum([sum(JuMP.value.(m.ext[:variables][:export][country,neighbor,t]
        #     for neighbor in m.ext[:sets][:connections][country])) for t in 1:endtime])
        imported = sum(JuMP.value.(m.ext[:variables][:import]))
        exported = sum(JuMP.value.(m.ext[:variables][:export]))
    elseif type == "NTC"
        imported = sum([sum(JuMP.value.(m.ext[:variables][:import][country,neighbor,t] for neighbor in m.ext[:sets][:connections][country])) for t in timesteps])
        exported = sum([sum(JuMP.value.(m.ext[:variables][:export][country,neighbor,t] for neighbor in m.ext[:sets][:connections][country])) for t in timesteps])
    end

    row = DataFrame(
        "scenario" => scenario,
        "end" => endtime,
        "year" => year,
        "CY" => CY,
        "CY_ts" => CY_ts,
        "VOLL" => VOLL,
        "type" => type,
        "CO2_cost"=>sum(JuMP.value.(m.ext[:expressions][:CO2_cost][country,tech,t] for tech in m.ext[:sets][:dispatchable_technologies][country] for t in 1:endtime)),
        "load_shedding_cost"=>sum(JuMP.value.(m.ext[:expressions][:load_shedding_cost][country,t] for t in 1:endtime)),
        "VOM_cost"=>sum(JuMP.value.(m.ext[:expressions][:VOM_cost][country,tech,t] for tech in m.ext[:sets][:technologies][country] for t in 1:endtime)),
        "fuel_cost"=>sum(JuMP.value.(m.ext[:expressions][:fuel_cost][country,tech,t] for tech in m.ext[:sets][:dispatchable_technologies][country] for t in 1:endtime)),
        "investment_cost"=>sum(JuMP.value.(m.ext[:expressions][:investment_cost][country,tech] for tech in m.ext[:sets][:investment_technologies][country])),
        "CCGT"=> JuMP.value.(m.ext[:variables][:invested_cap][country,"CCGT"]),
        "OCGT"=> JuMP.value.(m.ext[:variables][:invested_cap][country,"OCGT"]),
        "PV"=> JuMP.value.(m.ext[:variables][:invested_cap][country,"PV"]),
        "w_on"=> JuMP.value.(m.ext[:variables][:invested_cap][country,"w_on"]),
        "w_off"=> JuMP.value.(m.ext[:variables][:invested_cap][country,"w_off"]),
        "imported" => imported,
        "exported" => exported,
        "demand" => demand,
        "peak_demand" => peak_dem
    )
    return row
end

function build_isolated!(m,endtime,scenario,year,CY,CY_ts,country,VOLL)
    #We start by redefining the sets here, to remove unnecessary countries. 
    all_countries = [key for key in keys(m.ext[:sets][:technologies])]
    define_sets!(m,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
    process_parameters!(m,scenario,year,CY,[country])
    process_time_series!(m,scenario,year,CY_ts)
    remove_capacity_country!(m,country)
    build_isolated_investment_model!(m,endtime,VOLL)
end

function build_NTC!(m,endtime,scenario,year,CY,CY_ts,country,VOLL,transp_cost)
    process_parameters!(m,scenario,year,CY,[country])
    process_time_series!(m,scenario,year,CY_ts)
    remove_capacity_country!(m,country)
    build_NTC_investment_model!(m,endtime,VOLL,transp_cost)
end

function build_with_trade_curves!(m,endtime,scenario,year,CY,CY_ts,country,VOLL,transport_cost)
    #We start by redefining the sets here, to remove unnecessary countries. 
    all_countries = [key for key in keys(m.ext[:sets][:technologies])]
    define_sets!(m,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
    process_parameters!(m,scenario,year,CY,[country])
    process_time_series!(m,scenario,year,CY_ts)
    remove_capacity_country!(m,country)

    #Obtain trade availability ts 
    file_name_ext = "$(country)_$(year)_CY_$(CY_ts)_$(endtime)"
    path = joinpath("Results","TradeCurves","import_price_curves$(scenario)_$(file_name_ext).csv")

    trade_curves = CSV.read(path,DataFrame)

    add_availability_curves_to_model!(m,trade_curves)

    build_single_trade_curve_investment_model!(m,endtime,VOLL,transport_cost)
end


