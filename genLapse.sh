FPS=12
#bitrate="-b 1000k -bt 1300k"
bitrate="-b 4000k -bt 4500k"

imgdir=img/
pass1preset=slowfirstpass
#pass2preset=max
pass2preset=hq

# http://www.fscience.net/ffmpeg/avcodec_8h.html#ad384ee5a840bafd73daef08e6d9cafe7
# looks like these flags are offset from enum vals by one

# try to set rec709/sRGB/0-255 flags here... all that truncation and rec 601 is just shitting
# on all of colorimetry :S This however means that when the user/driver/media player decides
# to perform 16-235 -> 0-255 conversion out of a fad, the image contrast will get too high.
# It seems to be either that or fucked up colors, because apparently some guys writing codecs,
# players and standards are fuck-ups.

# options="-vcodec libx264 $bitrate -r $FPS -colorspace 1 -color_primaries 1 -color_trc 1 -color_range 2"
# chromaCoords="\"pc.709\""

# mpeg-style settings :S

options="-vcodec libx264 $bitrate -r $FPS"
chromaCoords="\"rec709\""

rm imageList.avs 2> /dev/null
touch imageList.avs

prefix=""
for f in ${imgdir}/*.jpg
do
	printf "$prefix ImageSource(\"${f}\", 0, 0, $FPS, true).ConvertToYV12(matrix=${chromaCoords}) \\\\\\n" >> imageList.avs
	prefix="+"
done

printf "\\n\\n" >> imageList.avs
#printf "ColorMatrix(mode=\"Rec.709->Rec.601\")\\n" >> imageList.avs
unset prefix

infile=imageList.avs
outfile='lapse.mkv'
commonopts='-threads 4'

ffmpeg/bin/ffmpeg -y -i "$infile" -an -pass 1 $commonopts -fpre presets/libx264-${pass1preset}.ffpreset $options "$outfile"
#audio=-acodec libfaac -ar 44100 
audio=-an
ffmpeg/bin/ffmpeg -y -i "$infile" $audio -ab 96k -pass 2 $commonopts -fpre presets/libx264-${pass2preset}.ffpreset $options "$outfile"

rm imageList.avs

