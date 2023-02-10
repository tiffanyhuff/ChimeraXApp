FROM openjdk:17.0.2-jdk

RUN microdnf upgrade && \
    microdnf install libXext libXrender libXtst

#FROM ubuntu:20.04

#RUN apt-get install -y python3-pip \
#    && apt-get install wget -y \ 
#    && curl -O https://bootstrap.pypa.io/pip/3.6/get-pip.py \
#    && python3 get-pip.py \

#RUN wget -O ADFR.tar  https://ccsb.scripps.edu/adfr/download/1038/ \
#    && tar -xf ADFR.tar \
#    && cd ADFRsuite_x86_64Linux_1.0 \ 
#    && ./install.sh -c 0 \
#    && cd 

# Set path to include ADFR scripts
#ENV PATH="$PATH:/ADFRsuite_x86_64Linux_1.0/bin"


#COPY ucsf-chimerax_1.5ubuntu20.04_amd64.deb  /

# https://www.rbvi.ucsf.edu/chimerax/cgi-bin/secure/chimerax-get.py?file=1.5/ubuntu-22.04/ucsf-chimerax_1.5ubuntu22.04_amd64.deb

# Fix hash sum mismatch issue. For more details, see
# https://forums.docker.com/t/hash-sum-mismatch-writing-more-data-as-expected/45940/2
#COPY badproxy /etc/apt/apt.conf.d/99fixbadproxy

#RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
#        /ucsf-chimerax_1.5ubuntu20.04_amd64.deb \
#    && rm /ucsf-chimerax_1.5ubuntu20.04_amd64.deb
