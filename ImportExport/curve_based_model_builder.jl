include("model_builder.jl")

function price_curves_to_availability_curves(curves)
    # Firs, extract all unique prices: 
    prices_sorted = sort(unique(Matrix(curves)))
    trade_levels = parse.(Int,names(curves))
    trade_level_step = trade_levels[1] - trade_levels[2]

    #Then, for each price, find the availability 
    counts_per_row = Dict()
    import_available = Dict()
    export_available = Dict()


    n_cols = size(curves, 2)  # Get the total number of columns
    midpoint = div(n_cols, 2)  # Calculate the midpoint
    export_columns = curves[:, (midpoint+2):end]
    import_columns = curves[:, 1:midpoint]

    for this_price in prices_sorted
        counts_per_row[this_price] = []
        import_available[this_price] = []
        export_available[this_price] = []
        for (curves_row,import_row,export_row) in zip(eachrow(curves),eachrow(import_columns),eachrow(export_columns))
            count = sum(skipmissing(curves_row) .== this_price)
            push!(counts_per_row[this_price], count)
            count_import = sum(skipmissing(import_row) .== this_price)
            push!(import_available[this_price], count_import*trade_level_step)
            count_export = sum(skipmissing(export_row) .== this_price)
            push!(export_available[this_price], count_export*trade_level_step)
        end
    end
    return import_available,export_available
end

function add_availability_curves_to_model!(m,curves)
    import_availability,export_availability = price_curves_to_availability_curves(curves)
    all_prices = sort(collect(keys(import_availability)))

    #Add price leves to sets 
    m.ext[:sets][:trade_prices] = all_prices
    m.ext[:sets]
    #Add timeseries of each price_level to timeseries
    m.ext[:timeseries][:trade] = Dict()
    m.ext[:timeseries][:trade][:import] = import_availability
    m.ext[:timeseries][:trade][:export] = export_availability
end

function build_single_trade_curve_investment_model!(m::Model,endtime,VOLL,transport_cost)

    build_base_investment_model!(m,endtime,VOLL)

    countries = m.ext[:sets][:countries]
    timesteps = 1:endtime
    storage_technologies = m.ext[:sets][:storage_technologies]
    trade_prices = m.ext[:sets][:trade_prices]

    total_production_timestep = m.ext[:expressions][:total_production_timestep]
    load_shedding = m.ext[:variables][:load_shedding]
    curtailment = m.ext[:variables][:curtailment]
    charge = m.ext[:variables][:charge]

    VOM_cost = m.ext[:expressions][:VOM_cost]
    fuel_cost = m.ext[:expressions][:fuel_cost]
    load_shedding_cost = m.ext[:expressions][:load_shedding_cost]
    CO2_cost = m.ext[:expressions][:CO2_cost]
    investment_cost = m.ext[:expressions][:investment_cost]


    demand = m.ext[:timeseries][:demand]
    import_availability = m.ext[:timeseries][:trade][:import]
    export_availability = m.ext[:timeseries][:trade][:export]


    #Variables for import and export 
    import_v = m.ext[:variables][:import]  = @variable(m,[c= countries, p=trade_prices,time=timesteps],base_name = "import_v")
    export_v = m.ext[:variables][:export]  = @variable(m,[c= countries, p=trade_prices,time=timesteps],base_name = "export_v")

    #Add expression representing cost of import and export 
    
    
    trade_premium = m.ext[:expressions][:trade_cost] =
    @expression(m, [c = countries, p = trade_prices, time = timesteps],
    import_v[c,p,time]*transport_cost + export_v[c,p,time]*transport_cost
    )

    import_cost = m.ext[:expressions][:import_cost] =
    @expression(m, [c = countries, p = trade_prices, time = timesteps],
    import_v[c,p,time]*p
    )
    export_revenue = m.ext[:expressions][:export_revenue] =
    @expression(m, [c = countries, p = trade_prices, time = timesteps],
    export_v[c,p,time]*p
    )


    #Import availability 
    m.ext[:constraints][:import_restrictions] = @constraint(m,[c = countries, p = trade_prices, time = timesteps],
    ##TODO, there is no country index here while it is present in the constraints and vars, bit weird maybe
        0 <= import_v[c,p,time] <= import_availability[p][time]
    )
    #Export availability 
    m.ext[:constraints][:export_restrictions] = @constraint(m,[c = countries, p = trade_prices, time = timesteps],
    ##TODO, there is no country index here while it is present in the constraints and vars, bit weird maybe
        0 <= export_v[c,p,time] <= export_availability[p][time]
    )

    # Demand met for all timesteps
    m.ext[:constraints][:demand_met] = @constraint(m,[c = countries, time = timesteps],
        total_production_timestep[c,time] + load_shedding[c,time] - curtailment[c,time] + sum(import_v[c,p,time] for p in trade_prices)  == demand[c][time] +  sum(export_v[c,p,time] for p in trade_prices)  + sum(charge[c,tech,time] for tech in storage_technologies[c])
    )

    m.ext[:objective] = @objective(m,Min,sum(investment_cost) + sum(VOM_cost) + sum(CO2_cost) + sum(fuel_cost) + sum(load_shedding_cost) + sum(trade_premium) + sum(import_cost) - sum(export_revenue))
end