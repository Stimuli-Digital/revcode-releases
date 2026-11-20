# syntax=docker/dockerfile:1
FROM nginx:stable-alpine@sha256:caf4e1e032a20f9c3c5e28fc7f25ffd768ad8677b4975c54193075997b3a97e3
COPY default.conf /etc/nginx/conf.d/default.conf
ADD --checksum=sha256:d5d785804120140c89722fb994232e3c25231f7183d3dd04ec75b17a9821c6d6 https://github.com/Stimuli-Digital/revcode-releases/releases/download/v0.63.7/Revcode_0.63.7_x64_en-US.msi /srv/releases/v0.63.7/Revcode_0.63.7_x64_en-US.msi
RUN chmod 644 /srv/releases/v0.63.7/Revcode_0.63.7_x64_en-US.msi && nginx -t
EXPOSE 8080
