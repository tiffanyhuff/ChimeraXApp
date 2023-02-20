FROM openjdk:17.0.2-jdk

RUN microdnf upgrade && \
    microdnf install libXext libXrender libXtst