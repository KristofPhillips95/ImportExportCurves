include("model_builder.jl")
import Gurobi

function optimize_and_retain_intertemporal_decisions_no_DSR(; scenario::String,year::Int,CY_cap::Int,CY_ts::Int,endtime::Int,VOLL::Int)
    m = Model(optimizer_with_attributes(Gurobi.Optimizer))
    define_sets!(m,scenario,year,CY_cap,[])
    process_parameters!(m,scenario,year,CY_cap)
    process_time_series!(m,scenario,year,CY_ts)
    #update_technologies_past_2040(m,ty)
    build_NTC_dispatch_model!(m,endtime,VOLL,0.1)
    #set_optimizer_attribute(m, "Method", 1)
    optimize!(m)
    soc = JuMP.value.(m.ext[:variables][:soc])
    production = JuMP.value.(m.ext[:variables][:production])

    return m,soc,production
end

function write_sparse_axis_to_dict(sparse_axis)
    dict =  Dict()
    for key in eachindex(sparse_axis)
        dict[key] = sparse_axis[key]
    end
    return dict
end

function build_model_for_import_curve(m,import_level,country,endtime,soc,production,transp_cost,VOLL)
    # m = Model(optimizer_with_attributes(Gurobi.Optimizer))
    # define_sets!(m,scenario,year,CY)
    # process_parameters!(m,scenario,year,CY)
    # process_time_series!(m,scenario)
    remove_capacity_country!(m,country)
    set_demand_country(m,country,import_level)
    build_NTC_dispatch_model!(m,endtime,VOLL,transp_cost)
    fix_soc_decisions(m,soc,production,1:endtime,country)
    #optimize!(m)
    return m
end

function build_model_for_import_curve_from_dict(import_level,country,endtime,soc,production,transp_cost)
    m = Model(optimizer_with_attributes(Gurobi.Optimizer))
    define_sets!(m,scenario,year,CY_cap,[])
    process_parameters!(m,scenario,year,CY_cap)
    process_time_series!(m,scenario,year,CY_ts)
    remove_capacity_country!(m,country)
    set_demand_country(m,country,import_level)
    build_NTC_dispatch_model!(m,endtime,VOLL,transp_cost)
    fix_soc_decisions_from_dict(m,soc,production,1:endtime,country)
    #optimize!(m)
    return m
end

function change_import_level!(m,endtime,import_level,country)
    for t in 1:endtime
        set_normalized_rhs(m.ext[:constraints][:demand_met][country,t],import_level)
    end
end

#Some functions that check if expected values are indeed found for import-curve models
function check_equal_soc_for_all_but(m1,m2,country,endtime)
    countries = filter(e->e !=country,m1.ext[:sets][:countries])
    soc_technologies = m1.ext[:sets][:soc_technologies]
    for country in countries
        # print(country)
        for tech in m1.ext[:sets][:soc_technologies][country]
            soc_1 = [JuMP.value.(m1.ext[:variables][:soc][country,tech,t]) for t in 1:endtime]
            soc_2 = [JuMP.value.(m2.ext[:variables][:soc][country,tech,t]) for t in 1:endtime]
            @assert(soc_1 == soc_2)

            prod_soc_1  = [JuMP.value.(m1.ext[:variables][:production][country,tech,t]) for t in 1:endtime]
            prod_soc_1  = [JuMP.value.(m2.ext[:variables][:production][country,tech,t]) for t in 1:endtime]
            @assert(soc_1 == soc_2)

        end
    end
end

function check_net_import(m,country,import_level,endtime)
    net_import = [sum(JuMP.value.(m.ext[:variables][:import][country,nb,t]) - JuMP.value.(m.ext[:variables][:export][country,nb,t]) for nb in m.ext[:sets][:connections][country]) for t in 1:endtime]
    for t in 1:endtime
        @assert( round(net_import[t] + JuMP.value.(m.ext[:variables][:load_shedding][country,t]) ,digits = 3)  == import_level)
    end
end

function check_charge_zero(m,country,endtime)
    for t in 1:endtime
        ls = sum(JuMP.value.(m.ext[:variables][:charge][country,tech,t]) for tech in m.ext[:sets][:storage_technologies][country])
        @assert( round(ls, digits=3) == 0 )
    end
end

function check_production_zero!(m,country,endtime)
    for t in 1:endtime
        for tech in m.ext[:sets][:technologies][country]
            @assert(JuMP.value.(m.ext[:variables][:production][country,tech,t]) == 0)
        end
    end
end

function write_prices(curve_dict,scenario,import_levels,file_name_ext)
    df_prices = DataFrame()

    for price in import_levels
        insertcols!(df_prices,1,string(price) => curve_dict[price])
    end
    path = joinpath("Results","TradeCurves","import_price_curves$(scenario)_$(file_name_ext).csv")

    CSV.write(path,df_prices)
end