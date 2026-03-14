# ibkr stream service idealization 
goal: 
- everything below should be hosted on this OCI server for simplicity of access. 
- Be able to create websocket string of instruments that is of interest to me for high frequency trading
 for high frequency trading for high frequency trading
- Be able to create webs. Restful API calls to get 10 minute interval historical data for the entirety of a market for trading which includes US market and Australian market as well as Bitcoin and CFDS
- Store the data in a compact format that is easy to be able to be queryed and analysed on a live basis with strategies that are efficient I guess we can start with Python for back testing but then after we've confirmed the strategy we might want to migrate into a language that is more efficient to run and execute so that there are less latency especially for high frequency trading but like for the 10 minute interval one it probably doesn't matter we can probably just stick with the python version
- In order to run the 10 minute interval one we could do cron job within container for ease of deployment
- if the strategy is python then  lets use uv to minimize infra cost
- Please compare and research in detail in what scenario can we use the IBKR rest API and when do we need to use their like Docker container client and or gateway or something like that API gateway
- Please plan out the complete architecture to and self contained infra that is required to do both the live execution as well a....alysis and back testing of strategies
 do both the live execution as well as exploratory data analysis and back testing of strate do both the live execution as well as exploratory data analysis and back testing of strategies
- Do we need like AGUI access to the instance to be able to achieve what we need here or like is vs code or the thing that's called like a code server that we're currently planning to set up but not yet haven't yet got to enough that also that code server thing also include like a file explorer I think web ui container


