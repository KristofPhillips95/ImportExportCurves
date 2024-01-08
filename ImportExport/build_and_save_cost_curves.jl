include("cost_curves_builder.jl")
import JSON3

function build_and_save_cost_curves(; global_param_dict::Dict,save_soc = true)
    endtime = global_param_dict["endtime"]
    CY = global_param_dict["Climate_year"]
    CY_ts = global_param_dict["Climate_year_ts"]
    VOLL = global_param_dict["ValOfLostLoad"]
    scenario = global_param_dict["scenario"]
    year = global_param_dict["year"]
    stepsize = global_param_dict["stepsize"]
    
    #Optimize dispatch model with given capacities from input data
    m,soc,production =  optimize_and_retain_intertemporal_decisions_no_DSR(; scenario = scenario,year=year,CY_cap = CY,CY_ts = CY_ts,endtime = endtime,VOLL=VOLL)

    if save_soc
        save_intertemporal_decisions(soc,production,year,scenario,endtime,CY_ts)
    end

    country = global_param_dict["country"]
    trade_levels = get_trade_levels(m = m, country = country,stepsize = stepsize)

    m = build_model_for_import_curve(m,0,country,endtime,soc,production,0,VOLL)
    trade_curve_dict = Dict()

    for trade_level in trade_levels
        change_import_level!(m,endtime,trade_level,country)
        optimize!(m)
        check_production_zero!(m,country,endtime)
        check_net_import(m,country,trade_level,endtime)
        import_prices = [JuMP.dual.(m.ext[:constraints][:demand_met][country,t]) for t in 1:endtime]
        trade_curve_dict[trade_level] = import_prices
    
    end
    write_prices(trade_curve_dict,scenario,trade_levels,"$(country)_$(year)_CY_$(CY_ts)_$(endtime)")
end 


function save_intertemporal_decisions(soc,production,year,scenario,endtime,CY_ts)
    #Save the soc and production levels of dispatch model
    open(joinpath("Results","soc_files","soc_$(year)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
        JSON3.write(io, write_sparse_axis_to_dict(soc))
    end


    open(joinpath("Results","soc_files","prod_$(year)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
        JSON3.write(io, write_sparse_axis_to_dict(production))
    end
end 

function get_trade_levels(; m,country,stepsize = 100)
    cap_import = sum(maximum.(values(m.ext[:parameters][:connections][country])))
    cap_export = sum(maximum.(m.ext[:parameters][:connections][neighbor][country] for neighbor in m.ext[:sets][:connections][country]))

    min_level = floor(cap_export/stepsize)*stepsize
    max_level = floor(cap_import/stepsize)*stepsize
    import_levels  = -min_level:stepsize:max_level
    return import_levels
end

