function importScripts()
    package_root = dirname(dirname(dirname(dirname(@__DIR__))))
    
    [include(joinpath(package_root, "src", "structs", jl_file)) for jl_file in [
                                                                    "ChromObject.jl",
                                                                    "ArrayDict.jl",
                                                                    "Counter.jl",
                                                                    "Ion.jl",
                                                                    "LibraryIon.jl",
                                                                    "MatchIon.jl",
                                                                    "LibraryFragmentIndex.jl",
                                                                    "SparseArray.jl",
                                                                    "fastaEntry.jl",
                                                                    "fragBoundModel.jl",
                                                                    "modelTypes.jl"]];
    #Utilities
    [include(joinpath(package_root, "src","utils", jl_file)) for jl_file in [

                                                                    "isotopes.jl",
                                                                    "globalConstants.jl",
                                                                    "uniformBasisCubicSpline.jl",
                                                                    "isotopeSplines.jl",
                                                                    "normalizeQuant.jl",
                                                                    "massErrorEstimation.jl",
                                                                    "SpectralDeconvolution.jl",
                                                                    "percolatorSortOf.jl",
                                                                    "plotRTAlignment.jl",
                                                                    "probitRegression.jl",
                                                                    "partitionThreadTasks.jl",
                                                                    "max_lfq.jl",
                                                                    "scoreProteinGroups.jl",
                                                                    "wittakerHendersonSmoothing.jl",
                                                                    "getBestTrace.jl",
                                                                    "getCVFolds.jl",
                                                                    "getBestPSMs.jl",
                                                                    "mapLibraryToEmpiricalRT.jl",
                                                                    "getBestPrecursorsAccrossRuns.jl",
                                                                    "getIrtErrs.jl",
                                                                    "getPSMsPassingQVal.jl",
                                                                    "samplePsmsForXgboost.jl",
                                                                    "mergePsmTables.jl",
                                                                    "summarizeToProtein.jl",
                                                                    "writeCSVTables.jl"]];

    [include(joinpath(package_root,"src","PSM_TYPES", jl_file)) for jl_file in ["PSM.jl","spectralDistanceMetrics.jl","UnscoredPSMs.jl","ScoredPSMs.jl"]];
    #Files needed for PRM routines
    [include(joinpath(package_root,"src","Routines","LibrarySearch","methods",jl_file)) for jl_file in [
                                                                                    "parseFileNames.jl",
                                                                                    "makeOutputDirectories.jl",
                                                                                    "parseParams.jl",
                                                                                    "matchPeaks.jl",
                                                                                    "buildDesignMatrix.jl",
                                                                                    "manipulateDataFrames.jl",
                                                                                    "buildRTIndex.jl",
                                                                                    "searchRAW.jl",
                                                                                    "selectTransitions.jl",
                                                                                    "integrateChroms.jl",
                                                                                    "queryFragmentIndex.jl"]];

    #Files needed for PRM routines
    [include(joinpath(package_root,"src","Routines","LibrarySearch",jl_file)) for jl_file in [
                                                                                    "parameterTuningSearch.jl",
                                                                                    "firstSearch.jl",
                                                                                    "quantitativeSearch.jl",
                                                                                    "scoreTraces.jl",
                                                                                    "secondQuant.jl",
                                                                                    "proteinQuant.jl",
                                                                                    "qcPlots.jl",
                                                                                    "huberLossSearch.jl"]];                                                                                      

                                                                                                                                
    [include(joinpath(package_root,"src","Routines","BuildSpecLib",jl_file)) for jl_file in [
    "PioneerLib.jl",
    "buildPioneerLib.jl",  
    "buildUniSpecInput.jl",
    "estimateCollisionEv.jl",
    "fragBounds.jl",
    "getIonAnnotations.jl",
    "getMZ.jl",
    "koinaRequests.jl",
    "paramsChecks.jl",
    "parseChronologerResults.jl",
    "parseFasta.jl",
    "parseIonAnnotations.jl",
    "parseIsotopeMods.jl",
    "parseKoinaFragments.jl",
    "prepareChronologerInput.jl"
    ]];

end