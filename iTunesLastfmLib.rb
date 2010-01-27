require 'rexml/document'
require 'rack'
require 'net/http'
require 'uri'
require 'id3lib'
require 'cgi'


class iTunesLastfmLib
   attr_accessor :itunes_xml_path, :logfile_path, :image_path, :in_control_mode, :cuts
   
   

   def initialize
      @itunes_xml_path = ""  
      @logfile_path = ""
      @image_path = ""
      @in_control_mode = true #this one better be defined right away
      @cuts = []
   end
   
   

   def get_image(image_link, images_num, image_index, artist, location)
      # receives an image link, the number of images available for that artist
      # and the index of the currently being processed image on the array of images
      # stores the image in a file in the @image_path folder and ask de user if it accepts the image
      # returns :skip if the user decides to skip the track
      # returns :next if the user doesn't want the current image
      # returns :accept if the user accepts the image
   
      url = URI.parse(image_link)
   
      http2 = Net::HTTP.new(url.host)
      http2.start do |http2| 
         # connection for retriving the image
    
         imagereq = Net::HTTP::Get.new(url.path)
         imageresp = http2.request(imagereq)
         imageresp.value   
         f = File.new(@image_path+Rack::Utils.escape(artist)+".jpg", "wb+")
         f << imageresp.body
         f.close
         #image stored in the images directory!
   
         #if control_mode is set to false the current image is always accepted
         return :accept unless @in_control_mode

         #otherwise...
         puts "Image #{image_index +1}/#{images_num} for #{artist} retrieved\nThe file is at #{location}\nDo you accept the image? (y/n/leave)"
         input = STDIN.gets
         if input == "y\n"
            # the user accepts the image chosen, leave the infinite cycle
            return :skip
         elsif input == "leave\n"
            return :next
         elsif "n\n"
            return :accept
         end
      end
   rescue Net::HTTPExceptions => e
      @logfile << "[Error3] Image #{image_index + 1}/#{images_num } for #{artist} at #{location} could not be retrived\n"
      @logfile.flush
      raise e
   end
   
   


   def get_artwork(track)
      @logfile << "Getting artwork...\n"
   
      artist = track[:artist]

      http = Net::HTTP.new("ws.audioscrobbler.com")
      http.start do |http| 
         #connection to retrieve the list of links to images for the artist specified
         request = Net::HTTP::Get.new("/2.0/?method=artist.getimages&artist=#{Rack::Utils.escape(artist)}&api_key=9e19622c4e115423ad17b690ca502c18")
         response = http.request(request)
         response.value
         images = response.body.scan(/<size name="extralarge" width="\d+" height="\d+">(.*)<\/size>/u)
         if images[0] #if it enters it means there are images for that artist
            i = 0
            until [:accept, :skip].include? (answer = get_image(images[i][0], images.size, i, artist, track[:location]))
               #the response from get_image will be either :accept, :skip or :next, only if it's :next 
               # we continue to pull images from the server
               # the script will rotate forever between the images of each artist until you 
               # answer yes (accept the picture) or enter "leave" for skipping that track
               i = (i + 1) % images.size
            end
            @map[:"#{artist}"] = answer #either if we skip or accept, the choice must be remembered
         else 
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
   
   


   def apply_artwork(track)
      # the artwork if on the images folder and the name of the image
      # is the escaped version of track[:artist]
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



   def parse_itunes_library
      f = File.open(@itunes_xml_path, "r")
      doc = REXML::Document.new(f)

      tracks = []
      #parsing the XML file
      doc.root.elements["dict/dict/"].each do |el|
         #our tracks are inside three nested <dict> tags
         # we will store for each track its path and artist if defined
      	artist = el.to_s.scan(/<key>Artist<\/key><string>(.*)<\/string>/u)[0]
      	location = el.to_s.scan(/<key>Location<\/key><string>(.*)<\/string>/u)[0]
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
   
   


   def track_already_has_pic(track)
      #we don't want to get album artwork for a track which already has pictures
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



   def start
      if  @itunes_xml_path != "" and @logfile_path != "" and @image_path != ""
         @logfile = File.new(@logfile_path, "a")
         @map = []

         #getting an array of tracks, composed of the pair artist and path
         tracks = parse_itunes_library()

         tracks.each do |track|
            begin
               @logfile << "Processing #{track[:artist]}\n";
      
               if !track_already_has_pic(track) 
                  status = @map[:"#{track[:artist]}"]
                  if status.nil?
                     get_artwork(track)
                  elsif status == :accept
                     @logfile << "Artwork already there for this artist\n"
                  else #if status == :skip
                     next #track
                  end
         
                  apply_artwork(track)
               else
                  @logfile << "Track already has pictures, skip\n\n\n"
               end
            rescue Exception => e
               @logfile << "[FAIL] because #{e}\n\n\n"
            end
         end

         @logfile.close
      else
         puts "One of the necessary variables for the script to run was not defined, check the documented examples"
      end
   end
end