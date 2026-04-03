ARG BASE_IMAGE="quay.io/rockylinux/rockylinux:9"
FROM ${BASE_IMAGE}

LABEL description="Dell Repository Manager (DRM)"

# Set working directory
WORKDIR /tmp

RUN curl -Ls https://dl.dell.com/FOLDER14174711M/1/DRMInstaller_3.5.0.76.bin \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36" \
    -o DRMInstaller.bin
RUN chmod +x DRMInstaller.bin
RUN ./DRMInstaller.bin -i silent
RUN rm -f DRMInstaller.bin

# Expose the default DRM service port
EXPOSE 8090

WORKDIR /opt/dell/dellrepositorymanager
CMD ["/opt/dell/dellrepositorymanager/DRM_Service.sh"]
