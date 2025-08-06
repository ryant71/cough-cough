# Cough Cough

## Why?

* I wanted to play around with Cloudformation
* I wanted to play around with "bootstrapping" an EC2
* I thought setting up transmission in a convoluted way would be interesting

## No, but why?

Very occasionally, I feel the need to download something that is best downloaded as a Torrent, and I am hesitant
to do so from my home computer. The reason for the hesitance is that the country I am in slaps heavy fines on
*cough*downloading*cough* and I don't trust VPNs to remain VPN-ing for the duration of the download.

I originally had this running on a shared virtual machine, but they cottoned onto what I was doing and pinched
certain types of network traffic. EC2 seemed a good alternative, because they can be spun up and then spun down
very quickly if one uses IaC and each time, one gets a new IP. I also don't think that AWS is in a position to 
track this sort of thing unless someone doing it on a huge scale. And, like I said, I do this infrequently for
downloads that are generally not available elsewhere. Amazon Prime, Netflix, Apple TV, and a few smaller streaming
services are still getting their pound of flesh. As are Spotify, Apple whatever, Bandcamp, and SoundCloud.

## Components

* Cloudformation
* But, first, an AWS account
* An S3 bucket (soon to be a CFN template)
* Scripts to manage stacks
* Configuration scripts to run on the EC2
* A template config for Nginx

