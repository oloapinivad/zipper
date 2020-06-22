# Zipper v0.1
## A tool for compressing NetCDF files to NetCDF4 Zip

Jun 2020

This is nothing more than a bash utility based on nccopy which looks for all the netcdf files you have in a local directory and trying to convert them to NetCDF4 Zip format.
Only files which are not compressed will be affected. Timestamps, permissions and ownership will be preserved (you may need to run it as root).
Detailed reports on occupancy and gained space are produced.   

