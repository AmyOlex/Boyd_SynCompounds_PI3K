# Amy Olex
# 4/22/20
# Dead Cell Removal Process
# This Script is to identify a list of dead cells and cells to keep for a single cell ranger aligned sample.
#
# This script reads in a config file that has the following information:
# Sample ID
# location of filtered_features_bc_matrix folder for the sample.
#
# The output files will be saved to the sudfolder "dead_cell_analysis" in the files live_cells.txt and 
# dead_cells.txt.  A text file with the dead cell filtering criteria and the violin image plots will also 
# be saved to this folder for reference.

library("Seurat")
library("readr")
library("png")
#library(dplyr)

library("optparse")

option_list = list(
  make_option(c("-r", "--runid"), type="character", default=NULL, 
              help="Required. A unique name for this analysis.", metavar="character"),
  make_option(c("-c", "--configfile"), type="character", 
              help="Required. Input config file with sample information.", metavar="character"),
  make_option(c("-m", "--mito"), type="character", 
              help="type of mitochondria gene list to use. Options are coding, noncoding, all (default = coding)", 
              default = "coding", metavar="character"),
  make_option(c("-s", "--species"), type="character", 
              help="species to use for mitochandria genes. Options are human, mouse, merged (default = human).",
              default = "human", metavar="character"),
  make_option(c("-d", "--datatype"), type="character",
              help="type of data being used, such as 10X generated data or public data not in 10X directory format. Options are 10x or custom (default = 10x).",
              default = "10x", metavar="character"),
  make_option(c("-f", "--mitoFile"), type="character", 
              help="The direct path to a mitochondria gene list file.", 
              default = NULL, metavar="character"),
  make_option(c("-o", "--outdir"), type="character", 
              help="output directory for results report (must already exist). Default is current directory.",
              default = "./", metavar="character")
#  make_option(c("--usegem"), type="logical", 
#              help="flags script to utilize the gem files associated with the inputs to create a second cells2keep file that includes all mouse cells from combined PDX samples.",
#              default = FALSE, action = "store_true", metavar="logical")
); 

opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

# test for NULL required arguments
if (is.null(opt$runid)){
  print_help(opt_parser)
  stop("A unique analysis name must be provided.", call.=FALSE)
}

if (is.null(opt$configfile)){
  print_help(opt_parser)
  stop("A configuration file with sample information must be provided.", call.=FALSE)
}

## configure the mitochandria file path
if (is.null(opt$mitoFile)){
  # If this was not provided, then use the mito and species information.
  mitoflag = paste0(opt$mito, opt$species)
  
  if(mitoflag %in% c("codingmerged", "noncodingmerged")){
    stop("Mito files for coding and noncoding merged genome files not avaliable.  Use --mitoFile option to specify a file.", call.=FALSE)
  }
  mitoFile <- switch(mitoflag, 
                    "codinghuman" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoCodingGenes13_human.txt", 
                    "noncodinghuman" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoNonCodingGenes24_human.txt", 
                    "allhuman" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoAllGenes37_human.txt", 
                    "codingmouse" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoCodingGenes13_mouse.txt", 
                    "noncodingmouse" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoNonCodingGenes24_mouse.txt", 
                    "allmouse" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoAllGenes37_mouse.txt", 
                    "allmerged" = "/home/scRNASeq/harrell_data/Harrell_SingleCellSequencing/referenceFiles/MitoMasterList_37_hg19mm10.txt")
  
  
} else {
  mitoFile <- opt$mitoFile
}

runID <- opt$runid
inFile <- opt$configfile
reportDir <- opt$outdir
reportName <- paste0(reportDir, runID, "_DeadCellReport.txt")

#### Ok, print out all the current running options as a summary.

print("Summary of input options:\n")
print(paste("Run Name:", runID))
print(paste("ConfigFile:", inFile))
print(paste("Report Output:", reportName))
print(paste("Mitochandria Gene List:", mitoFile))
#print(paste("Using GEM file?", usegem))


# Read in the provided config file and loop for each row.
toProcess = read.table(inFile, header=FALSE, sep="\t")

#toProcess = read.table("HCI1config.txt", header=TRUE, sep="\t", stringsAsFactors = FALSE)

print(paste(dim(toProcess)[1], " rows were found."))

## Import mito genes
if(file.exists(mitoFile)){
  mitogene_ids <- read.delim(mitoFile, header = FALSE, stringsAsFactors = FALSE)[[1]]
} else {
  stop(paste0("Mitochondria file provided does not exists: ", mitoFile), call.=FALSE)
}
g <- file(reportName, 'w')

writeLines(c("RunID\tSampleID\tKeptCells\tDeadCells\t%Removed\tMitoCutoff\tlog(nFeatureRange)\tlog(nCountRange)"), g)

for(i in 1:dim(toProcess)[1]){
  print(paste("Processing row", i, "from sample", toProcess[i,1]))
  
  sampleID <- as.character(toProcess[i,1])
  datadir <- as.character(toProcess[i,2])
  
  if(opt$datatype == "custom"){
    data10x <- datadir
  } else {
    data10x <- paste0(datadir, "/filtered_feature_bc_matrix/")
    }

  savedir <- paste0(datadir, "/analysis_deadcells/")
 # gemfile <- paste0(datadir, "/analysis/gem_classification.csv")
  
  print(paste("Saving file in: ", savedir))
  system(paste("mkdir", savedir))
  
  
  # Load the data set and create the Seurat object
  # scPDX.data <- Read10X(data.dir = paste0(datadir,"filtered_feature_bc_matrix"))
  scPDX.data <- Read10X(data.dir = data10x)
  
  # Initialize the Seurat object
  scPDX <- CreateSeuratObject(counts = scPDX.data, project = sampleID, min.cells = 0, min.features = 0)
  
  # add in mito gene percents and print violin plots

  mito <- mitogene_ids[mitogene_ids %in% row.names(scPDX)]
  scPDX[["percent.mt"]] <- PercentageFeatureSet(scPDX, features = mito)
  
  png(file = paste0(savedir, runID, "_", sampleID, "_MitoViolinPlot_BEFORE.png"), width = 2000, height = 1000, res = 200)

    print(VlnPlot(scPDX, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3, pt.size = .4))

  dev.off()
  
  
  ## Identify MAD cutoff
  my_mad <- mad(scPDX$percent.mt[scPDX$percent.mt <= 50])
  my_median <- median(scPDX$percent.mt[scPDX$percent.mt <= 50])
  
  mad3mt <- my_mad*3+my_median
  
  #mad3mt <- mad(scPDX$percent.mt)*3+median(scPDX$percent.mt)

  if(mad3mt > 25){
	print(paste("WARNING! Cutoff claculated to be > 25%: ", mad3mt, "\nSetting cutoff to 25%."))
	mad3mt <- 25
  }
  
  mad3countBelow <- median(log(scPDX$nCount_RNA)) - mad(log(scPDX$nCount_RNA))*3
  mad3featureBelow <- median(log(scPDX$nFeature_RNA)) - mad(log(scPDX$nFeature_RNA))*3
  
  mad3countAbove <- median(log(scPDX$nCount_RNA)) + mad(log(scPDX$nCount_RNA))*3
  mad3featureAbove <- median(log(scPDX$nFeature_RNA)) + mad(log(scPDX$nFeature_RNA))*3
  
  ## Identify Cells to keep and Cells that are dead
  mitokeep <- names(scPDX$percent.mt)[scPDX$percent.mt < mad3mt]
  
  countkeepBelow <- names(scPDX$nCount_RNA)[log(scPDX$nCount_RNA) > mad3countBelow]
  countkeepAbove <- names(scPDX$nCount_RNA)[log(scPDX$nCount_RNA) < mad3countAbove]
  countkeep <- intersect(countkeepAbove, countkeepBelow)
  
  featurekeepBelow <- names(scPDX$nFeature_RNA)[log(scPDX$nFeature_RNA) > mad3featureBelow]
  featurekeepAbove <- names(scPDX$nFeature_RNA)[log(scPDX$nFeature_RNA) < mad3featureAbove]
  featurekeep <- intersect(featurekeepBelow, featurekeepAbove)
  
  cellstokeep <- intersect(intersect(mitokeep, countkeep), featurekeep)
  deadcells <- scPDX@assays$RNA@data@Dimnames[[2]][!(scPDX@assays$RNA@data@Dimnames[[2]] %in% cellstokeep)]
  
  #if(usegem){
  #  ## import GEM file
  #  if(file.exists(gemfile)){
  #    gemdata <- read.delim(gemfile, header = TRUE, stringsAsFactors = FALSE, sep=",")
  #  } else {
  #    stop(paste0("GEM file does not exists: ", gemfile), call.=FALSE)
  #  }
  #  
  #  newcells2keep <- setdiff(gemdata$Barcode, deadcells)
  #  
  #  print("Notice! Using GEM file:")
  #  print(paste("Dead Cells Identified: ", length(deadcells)))
  #  print(paste("Original Cells to Keep: ", length(cellstokeep)))
  #  print(paste("GEM barcodes: ", length(gemdata$Barcode)))
  #  print(paste("GEM Cells to Keep: ", length(newcells2keep)))
  #  write.table(newcells2keep, paste0(savedir, runID, "_", sampleID,"_gemcellstokeep.csv"), quote=FALSE, row.names = FALSE, col.names=c("barcode"))
  #  
  #  ## overwrite the cells to keep list if usegem is present as we want to keep all cells from the merged files, not just the human ones.
  #  ##system(paste0("grep -F -v -f WHIM2-H_deadcells.csv gem_classification.csv | cut -f 1 -d , > newcell2keep.csv"))
  #}
  
  #Save Lists
  write.table(cellstokeep, paste0(savedir, runID, "_", sampleID,"_cellstokeep.csv"), quote=FALSE, row.names = FALSE, col.names=c("barcode"))
  write.table(deadcells, paste0(savedir, runID, "_", sampleID,"_deadcells.csv"), quote=FALSE, row.names = FALSE, col.names=c("barcode"))

  print(paste("Analysis Summary for ", runID, "_", sampleID, ":", sep=""))
  print(paste("Cells to Keep: ", length(cellstokeep)))
  print(paste("Dead Cells: ", length(deadcells)))
  print(paste("Percent Removed: ", round((length(deadcells)/(length(cellstokeep)+length(deadcells)))*100, digits=2)))
  print(paste("Mito Cutoff: ", round(mad3mt, digits=2), "%", sep=""))
  
  #Save Report
  f <- file(paste0(savedir, runID, "_", sampleID, "_report.txt"), 'w')
  writeLines(c("KeptCells\tDeadCells\t%Removed\tMitoCutoff\tlog(nFeatureRange)\tlog(nCountRange)",
               paste(length(cellstokeep), length(deadcells), round((length(deadcells)/(length(cellstokeep)+length(deadcells)))*100, digits=2), round(mad3mt, digits=2), paste0(round(mad3featureBelow, digits=2), "-",round(mad3featureAbove, digits=2)), paste0(round(mad3countBelow, digits=2),"-",round(mad3countAbove, digits=2)),  sep="\t")), f)
  close(f)
  
  writeLines(c(paste(runID, sampleID, length(cellstokeep), length(deadcells), round((length(deadcells)/(length(cellstokeep)+length(deadcells)))*100, digits=2), round(mad3mt, digits=2), paste0(round(mad3featureBelow, digits=2), "-",round(mad3featureAbove, digits=2)), paste0(round(mad3countBelow, digits=2),"-",round(mad3countAbove, digits=2)),  sep="\t")), g)
  
  
  #perform filtering and print out after violin plot
  scPDX_filt <- subset(scPDX, cells=cellstokeep)
  
  png(file = paste0(savedir, runID, "_", sampleID, "_MitoViolinPlot_AFTER.png"), width = 2000, height = 1000, res = 200)

    print(VlnPlot(scPDX_filt, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3, pt.size = .4))

  dev.off()
  
}

close(g)
print("Completed all samples!")

