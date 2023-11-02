include("ImportExport/model_builder.jl")
using Gurobi

scenario = "National Trends"
endtime = 240
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000

results = DataFrame()

isolated = false
country = "BE00"



for isolated in [true,false]
    for endtime in [240,480,720,8760]
        m = Model(optimizer_with_attributes(Gurobi.Optimizer))
        define_sets!(m,scenario,year,CY,[],[country])

        process_parameters!(m,scenario,year,CY,[country])
        process_time_series!(m,scenario,year,CY_ts)
        remove_capacity_country!(m,country)

        if isolated
            build_isolated_investment_model!(m,endtime,VOLL)
        else 
            build_NTC_investment_model!(m,endtime,VOLL,0.1)
        end
        optimize!(m)

        # print("Belgium isolated = ",isolated, JuMP.value.(m.ext[:variables][:invested_cap]))

        demand = sum(m.ext[:timeseries][:demand][country][1:endtime])
        if isolated 
            imported = 0
        else
            imported = sum([sum(JuMP.value.(m.ext[:variables][:import][country,neighbor,t]
                for neighbor in m.ext[:sets][:connections][country])) for t in 1:endtime])
        end

        row = DataFrame(
            "scenario" => scenario,
            "end" => endtime,
            "year" => year,
            "CY" => CY,
            "CY_ts" => CY_ts,
            "VOLL" => VOLL,
            "isolated" => isolated,
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
            "demand" => demand
        )
        results = vcat(results,row)

        CSV.write("Results\\model_results.csv",results)
    end
end