# Project Update - December 5
*** Josh Green and Akhil Sankar ***

Up to this point, both the SimpleScalar and ChampSim benchmarks have been set up, tested, and benchmarked using some default parameters. 

In terms of our goals, we have finished up through week 2, with the main milestones being benchmarking and setting up our toolchains.

An extensive environment was created to make customizing configurations easier and to automate any benchmarks and trials that we would want to run with SimpleScalar and ChampSim.

Up next would be implementing Victim Cache and Miss Cache implementations, followed by analyzing results, and finalizing any project documentation and presentations. 

In short, we have set up an environment to make our implementations easier to test. While this is probably on the overkill side, it should make our lives easier as we try to implement Victim Cache, and could be incredibly helpful if we implement other cache mechanisms as well (if time permits).

Instead of continuing on in this document, we am attaching  `README.md` and `environment.md` files that will give more context, as well as a zip file. The `environment.md` outlines how to utilize the environment. The `README.md` file outlines the project goals and directory structure. The zip file will contain all of the files within the environment except for this:
- `ChampSim/`, `simplesim-3.0/`, and `traces/` will not be in the zip file. These directories are very large and will cause the zip file to be very large (and consequently slow to download).
- To add the ChampSim and simplesim-3.0 directories correctly, clone the respective git repos from within the root directory and follow their install/setup instructions. To add the traces folder, just run `mkdir traces` from within project root as well.
