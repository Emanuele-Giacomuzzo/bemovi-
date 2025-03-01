######################################################################
# R script for analysing video files with BEMOVI (www.bemovi.info)
#
# Felix Moerman
# Computer = Mendel
# 12.01.2022 adapted by
# Samuel Huerlemann, Emanuele Giacomuzzo
######################################################################
rm(list=ls())
setwd('/media/mendel-himself/ID_061_Ema2/training_004_with_Felix/t1')

# load package
# library(devtools)
# install_github("femoerman/bemovi", ref="master")
library(bemovi)
library(parallel)
library(doParallel)
library(foreach)

#Define memory to be allocated
memory.alloc <- 240000 #-needs_to_be_specified
memory.per.identifier <- 40000 #-needs_to_be_specified
memory.per.linker <- 5000 #-needs_to_be_specified
memory.per.overlay <- 60000 #-needs_to_be_specified

# UNIX
# set paths to tools folder and particle linker
tools.path <- "/home/mendel-himself/bemovi_tools/" #-needs_to_be_specified
to.particlelinker <- tools.path

# directories and file names
to.data <- paste(getwd(),"/",sep="")
video.description.folder <- "0_video_description/"
video.description.file <- "video_description.txt"
raw.video.folder <- "1_raw/"
raw.avi.folder <- "1a_raw_avi/"
metadata.folder <- "1b_raw_meta/"
particle.data.folder <- "2_particle_data/"
trajectory.data.folder <- "3_trajectory_data/"
temp.overlay.folder <- "4a_temp_overlays/"
overlay.folder <- "4_overlays/"
merged.data.folder <- "5_merged_data/"
ijmacs.folder <- "ijmacs/"


######################################################################
# VIDEO PARAMETERS

# video frame rate (in frames per second)
fps <- 25 #-needs_to_be_specified

# length of video (in frames)
total_frames <- 125 #-needs_to_be_specified

#Dimensions of the videos in pixels
width=2048 #-needs_to_be_specified
height=2048 #-needs_to_be_specified

# measured volume (in microliter) #-needs_to_be_specified
measured_volume <- 34.4 # for Leica M205 C with 1.6 fold magnification, sample height 0.5 mm and Hamamatsu Orca Flash 4
#measured_volume <- 14.9 # for Nikon SMZ1500 with 2 fold magnification, sample height 0.5 mm and Canon 5D Mark III

# size of a pixel (in micrometer) #-needs_to_be_specified
pixel_to_scale <- 4.05 # for Leica M205 C with 1.6 fold magnification, sample height 0.5 mm and Hamamatsu Orca Flash 4
#pixel_to_scale <- 3.79 # for Nikon SMZ1500 with 2 fold magnification, sample height 0.5 mm and Canon 5D Mark III

# specify video file format (one of "avi","cxd","mov","tiff")
# bemovi only works with avi and cxd. other formats are reformated to avi below
video.format <- "cxd" #-needs_to_be_specified

# setup
difference.lag <- 10
thresholds <- c(13,255) # don't change the second value
# thresholds <- c(50,255)

# MORE PARAMETERS (USUALLY NOT CHANGED)
######################################################################
# FILTERING PARAMETERS 
# optimized for Perfex Pro 10 stereomicrocope with Perfex SC38800 (IDS UI-3880LE-M-GL) camera
# tested stereomicroscopes: Perfex Pro 10, Nikon SMZ1500, Leica M205 C
# tested cameras: Perfex SC38800, Canon 5D Mark III, Hamamatsu Orca Flash 4
# tested species: Tet, Col, Pau, Pca, Eug, Chi, Ble, Ceph, Lox, Spi

# min and max size: area in pixels
particle_min_size <- 10
particle_max_size <- 1000

# number of adjacent frames to be considered for linking particles
trajectory_link_range <- 3
# maximum distance a particle can move between two frames
trajectory_displacement <- 16

# these values are in the units defined by the parameters above: fps (seconds), measured_volume (microliters) and pixel_to_scale (micometers)
filter_min_net_disp <- 25
filter_min_duration <- 1
filter_detection_freq <- 0.1
filter_median_step_length <- 3

######################################################################
# VIDEO ANALYSIS

#Check if all tools are installed, and if not install them
check_tools_folder(tools.path)

#Ensure computer has permission to run bftools
system(paste0("chmod a+x ", tools.path, "bftools/bf.sh"))
system(paste0("chmod a+x ", tools.path, "bftools/bfconvert"))
system(paste0("chmod a+x ", tools.path, "bftools/showinf"))

# Convert files to compressed avi (takes approx. 2.25 minutes per video)
convert_to_avi(to.data, raw.video.folder, raw.avi.folder, metadata.folder, tools.path, fps, video.format)


# TESTING

# check file format and naming
# check_video_file_names(to.data,raw.avi.folder,video.description.folder,video.description.file)

# check whether the thresholds make sense (set "dark backgroud" and "red")
# check_threshold_values(to.data, raw.avi.folder, ijmacs.folder, 2, difference.lag, thresholds, tools.path,  memory.alloc)

# identify particles
locate_and_measure_particles(to.data, raw.avi.folder, particle.data.folder, difference.lag, min_size = particle_min_size, 
                             max_size = particle_max_size, thresholds=thresholds, tools.path, 
                             memory=memory.alloc, memory.per.identifier=memory.per.identifier, max.cores=detectCores()-1)

# link the particles
link_particles(to.data, particle.data.folder, trajectory.data.folder, linkrange = trajectory_link_range, disp = trajectory_displacement, 
               start_vid = 1, memory = memory.alloc, memory_per_linkerProcess = memory.per.linker, raw.avi.folder, max.cores=detectCores()-1, max_time = 1)

# merge info from description file and data
merge_data(to.data, particle.data.folder, trajectory.data.folder, video.description.folder, video.description.file, merged.data.folder)

# load the merged data
load(paste0(to.data, merged.data.folder, "Master.RData"))

# filter data: minimum net displacement, their duration, the detection frequency and the median step length
trajectory.data.filtered <- filter_data(trajectory.data, filter_min_net_disp, filter_min_duration, filter_detection_freq, filter_median_step_length)

# summarize trajectory data to individual-based data
morph_mvt <- summarize_trajectories(trajectory.data.filtered, calculate.median=F, write = T, to.data, merged.data.folder)

# get sample level info
summarize_populations(trajectory.data.filtered, morph_mvt, write=T, to.data, merged.data.folder, video.description.folder, video.description.file, total_frames)

# create overlays for validation
create.subtitle.overlays(to.data, traj.data=trajectory.data.filtered, raw.video.folder, raw.avi.folder, temp.overlay.folder, overlay.folder, fps,
                         vid.length=total_frames/fps, width, height, tools.path = tools.path, overlay.type="number", video.format)

# Create overlays (old method)
create_overlays(traj.data = trajectory.data.filtered, to.data = to.data, merged.data.folder = merged.data.folder, raw.video.folder = raw.avi.folder, temp.overlay.folder = "4a_temp_overlays_old/",
                overlay.folder ="4_overlays_old/", width = width, height = height, difference.lag = difference.lag, type = "traj", predict_spec = F, contrast.enhancement = 1, 
                IJ.path = "/home/mendel-himself/bemovi_tools", memory = memory.alloc, max.cores = detectCores()-1, memory.per.overlay = memory.per.overlay)

########################################################################
# some cleaning up
#system("rm -r 2_particle_data")
#system("rm -r 3_trajectory_data")
#system("rm -r 4a_temp_overlays")
system("rm -r ijmacs")
########################################################################

