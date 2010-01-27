require 'iTunesLastfmLib.rb'




script = iTunesLastfmLib.new
script.itunes_xml_path = "/Users/miguel/Music/iTunes 1/iTunes Library.xml"
#the path to the xml file of your iTunes library, it is usually
#stored in a folder named iTunes [number] inside your Music folder
script.logfile_path = "/Users/miguel/Desktop/errors.txt"
#a path to store the logfile which will give information
# about errors during the process of retriving and applying
# the album artwork, the file doesn't need to exist
script.image_path = "/Users/miguel/Desktop/images/"
# each image retrived will be stored there
# you'll have to delete the image after the script is over
# and you'll have to create this folder before the script starts
script.in_control_mode = true
# 'in control mode' asks for every artist if you accept the picture retrieved
# if you do not it shows you the next one on last.fm and asks again
# it will automatically rotate between all the pictures. Enter 'leave' to skip that track
# if none of the retrived pictures pleases you 
script.cuts = ["with", "With", "Feat", "feat", "pres", "Pres", ",", "vs", "&"]
# define words that will cut the the artist name so that something like
# Linkin Park feat. Jay-z just gets out as Linkin Park
# The cut is applied in the filter method
script.start
#here we go!
