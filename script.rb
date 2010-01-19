require 'rexml/document'
require 'rack'
require 'net/http'
require 'uri'
require 'id3lib'
require 'cgi'
require 'set'



###################################
#  DEFINE THE FOLLOWING VARIABLES #
###################################

@itunes_xml_path = "/Users/miguel/Music/iTunes 1/iTunes Library.xml"  
#the path to the xml file of your iTunes library, it is usually
#stored in a folder named iTunes [number] inside your Music folder
@logfile_path = "/Users/miguel/Desktop/errors.txt"
#a path to store the logfile which will give information
# about errors during the process of retriving and applying
# the album artwork, the file doesn't need to exist
@image_path = "/Users/miguel/Desktop/images/"
# each image retrived will be stored there
# you'll have to delete the image after the script is over
# and you'll have to create this folder before the script starts
@in_control_mode = true
# 'in control mode' asks for every artist if you accept the picture retrieved
# if you do not it shows you the next one on last.fm and asks again
# it will automatically rotate between all the pictures. Enter 'leave' to skip that track
# if none of the retrived pictures pleases you 
@cuts = ["with", "With", "Feat", "feat", "pres", "Pres", ",", "vs", "&"]
# define words that will cut the the artist name so that something like
# Linkin Park feat. Jay-z just gets out as Linkin Park
# The cut is applied in the filter method


##############################################
#       DON'T CHANGE ANYTHING AFTER THIS     #
#      unless you know what you're doing     #
#        (you probably do, anyway...)        #
##############################################



def get_artwork(track)
   @logfile << "Getting artwork...\n"
   
   artist = track[:artist]

   begin
      http = Net::HTTP.new("ws.audioscrobbler.com")
      http.start do |http| 
         #connection to retrieve the list of links to images for the artist specified
         request = Net::HTTP::Get.new("/2.0/?method=artist.getimages&artist=#{Rack::Utils.escape(artist)}&api_key=9e19622c4e115423ad17b690ca502c18")
         response = http.request(request)
         response.value
         images = response.body.scan(/<size name="extralarge" width="\d+" height="\d+">(.*)<\/size>/)
         if images[0] #if it enters it means there are images for that artist
            got = false; i = 1
            while true 
               # the script will rotate forever between the images of each artist until you 
               # answer yes (accept the picture) or enter "leave" for skipping that track
               if got
                  @logfile << "Artwork retrieved/chosen\n"
                  break
               end
               url = URI.parse(images[i][0])
               begin
                  http2 = Net::HTTP.new(url.host)
                  http2.start do |http2| 
                     # connection for retriving the image, before this we only had the link
                      
                     imagereq = Net::HTTP::Get.new(url.path)
                     imageresp = http2.request(imagereq)
                     imageresp.value   
                     f = File.new(@image_path+Rack::Utils.escape(artist)+".jpg", "wb+")
                     f << imageresp.body
                     f.close
                     #image stored in the images directory
                     
                     if @in_control_mode
                        puts "Image #{i} of #{images.size} images for #{artist} retrieved, do you accept the image? (y/n/leave)"
                        input = STDIN.gets
                        if input == "y\n"
                           # the user accepts the image chosen, leave the infinite cycle
                           got = true
                           @set << artist.to_sym
                           
                        else 
                           if input == "leave\n"
                              raise "None of the images chosen"
                           end
                        end
                           
                        i = (i + 1)
                        i = 1 if i > images.size
                     else
                        @set << artist.to_sym
                        got = true
                     end
                  end
               rescue Net::HTTPExceptions => e
                  @logfile << "[Error3] One of the images for #{artist} could not be retrived\n"
                  @logfile.flush
                  raise e
               end
            end # images[0].each
         else # unless images[0]
            @logfile << "[Error2] #{artist} has no images\n"
            @logfile.flush
            raise "artist has no images"
         end
      end
   rescue Net::HTTPExceptions => e
      @logfile << "[Error1] #{artist} api connection failed or artist not found\n"
      @logfile.flush
      raise e
   end
end


def apply_artwork(track)
   # the artwork if on the images folder and the name of the image
   # is the escaped version of track[:artist]
   begin
      path = track[:path]

      tag = ID3Lib::Tag.new(path)

      cover = {
        :id          => :APIC,
        :mimetype    => 'image/jpeg',
        :picturetype => 3,
        :textenc     => 0,
        :data        => File.read(@image_path+"#{Rack::Utils.escape(track[:artist])}.jpg")
      }
      tag << cover
      tag.update!
      
      @logfile << "Artwork applied\n\n"
   rescue Exception => e
      raise e
   end
end


def parse_itunes_library
   begin
      f = File.open(@itunes_xml_path, "r")
      doc = REXML::Document.new(f)

      tracks = []
      #parsing the XML file
      doc.root.elements["dict/dict/"].each do |el|
         #our tracks are inside three nested <dict> tags
         # we will store for each track its path and artist if defined
      	artist = el.to_s.scan(/<key>Artist<\/key><string>(.*)<\/string>/)[0]
      	location = el.to_s.scan(/<key>Location<\/key><string>(.*)<\/string>/)[0]
      	if artist and location and !location[0].include?("Podcasts") # for podcast filtering, I don't wanna mess with those
      	   artist = filter(CGI.unescape_html(artist[0])) # if artist is "ArtistX feat ArtistY" this may cut the text to just ArtistX
      	   location = location[0].gsub("file://localhost", "") #may not be needed
      	   location = Rack::Utils.unescape(location) #locations were escaped like .../Above%20%26Beyond/track1.mp3, we want them unescaped
      	   tracks << {:artist => artist, :path => location }
      	end
      end
   
      @logfile << "iTunes Library XML file processed\n"
   
      tracks
   rescue Exception => e
      raise e
   end
end


def track_already_has_pic(track)
   #we don't want to get album artwork for a track which already has pictures
   begin
      path = track[:path]
   
      tag = ID3Lib::Tag.new(path)
   
      tag.each do |frame|
         if frame[:id] == :APIC
            return true
         end
      end
   
      return false
   rescue Exception => e
      raise e
   end
end

def filter(artist)
   # applyes the cuts defined in @cuts
   #if an artist is "Linkin Park feat Jay-z" or "Beyoncé feat. Rihanna"
   # this funciton may cut the string to just keep the first artist
   # if and only of you define the splitting words
   @cuts.each do |cut|
      if artist.include?(cut) 
         return artist.split(cut)[0]
      end
   end
   
   return artist
end

##########################
# THE SCRIPT STARTS HERE #
##########################


@logfile = File.new(@logfile_path, "a")
@set = Set.new

#getting an array of tracks, composed of the pair artist and path
tracks = parse_itunes_library()

tracks.each do |track|
   begin
      @logfile << "Processing #{track[:artist]}\n";
      
      if !track_already_has_pic(track) 
         if !@set.include?(:"#{track[:artist]}") # the artist's artwork was already retrieved on another file, use the same
            get_artwork(track)
         else
            @logfile << "Artwork already there for this artist\n"
         end

         apply_artwork(track)
      else
         @logfile << "track already has pictures, skip\n\n\n"
      end
   rescue Exception => e
      @logfile << "[FAIL] because #{e}\n\n\n"
   end
end

@logfile.close

####################
#     THE END      #
####################
