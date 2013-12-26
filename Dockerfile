FROM ubuntu:precise
ENV DEBIAN_FRONTEND noninteractive
#
# resolvconf & fuse need some love to run in a container
# mitigate half configured packages by installing them separatly
#
RUN rm -f /etc/init/resolvconf.conf
ADD ntp_postinst /root/ntp_postinst
# cleanup on (re)start / setup console / maintain services
ADD lxc-cleanup.sh /sbin/lxc-cleanup.sh
RUN FROZEN_PACKAGES=$(grep FROZEN_PACKAGES= /sbin/lxc-cleanup.sh | awk -F'"' '{print $2}'|sed -re 's/"//g') &&\
    echo "lxc" > /run/container_type &&\
    sed -re 's/ main$/ main restricted universe multiverse/g' -e "s:/archive\.:/us.archive\.:g" -i /etc/apt/sources.list &&\
    echo "$FROZEN_PACKAGES on hold" &&\
    for i in $FROZEN_PACKAGES;do\
      echo $i hold | dpkg --set-selections;\
    done&&\
    grep "deb " /etc/apt/sources.list|sed -re "s/^deb /deb-src /g" >> /etc/apt/sources.list &&\
    apt-get -q update && apt-get upgrade -y --force-yes &&\
    apt-get install -y --force-yes apt-utils &&\
    if [ ! -e "/root/debbuild" ];then mkdir -pv /root/debbuild;fi &&\
    mv /root/ntp_postinst /root/debbuild &&\
    cd /root/debbuild;\
    nf=/etc/network/interfaces;\
    for i in resolvconf ntp;do \
      mkdir -p $i && cd $i &&\
      apt-get download -y $i &&\
      dpkg-deb -X $i*deb build &&\
      dpkg-deb -e $i*deb build/DEBIAN && \
      rm *deb && cd ..;done &&\
    cp /root/debbuild/ntp_postinst /root/debbuild/ntp/build/DEBIAN/postinst &&\
    echo "#!/bin/bash"   >/root/debbuild/resolvconf/build/DEBIAN/postinst &&\
    echo "exit 0"       >>/root/debbuild/resolvconf/build/DEBIAN/postinst &&\
    echo ""             >>/root/debbuild/resolvconf/build/DEBIAN/postinst &&\
    for i in resolvconf ntp;do\
      cd /root/debbuild/$i/build&&\
      dpkg-deb -b . /root/debbuild/$i.deb;\
    done&&\
    apt-get install -y $(dpkg-deb -I /root/debbuild/ntp.deb |egrep "^\s*Depends:"|sed -re "s/\([^\)]+\)//g" -e "s/,//g" -e "s/Depends://g") &&\
    for i in resolvconf ntp;do\
      dpkg -i /root/debbuild/$i.deb&&\
      echo $i hold | dpkg --set-selections;\
    done&&\
    apt-get -fy install &&\
    apt-get install -y --force-yes acpid;\
    apt-get install -y --force-yes cron;\
    apt-get install -y --force-yes logrotate;\
    apt-get install -y --force-yes libopts25;\
    apt-get install -y --force-yes net-tools;\
    apt-get install -y --force-yes rsyslog;\
    rm -rf /var/cache/apt/archives/*deb;
# Move those service away and make sure even if an upgrade spawn again
# the servvice file to mark it as-no-starting
# cleanup on (re)start / setup console / maintain services
ADD lxc-setup.conf /etc/init/lxc-setup.conf
ADD lxc-stop.conf /etc/init/lxc-stop.conf

RUN cd /;\
    for i in cron logrotate;do dpkg-reconfigure --force $i;done;\
    for i in /lib/init/fstab /etc/fstab;do echo > $i;done;\
    /usr/sbin/update-rc.d -f ondemand remove;\
    /sbin/lxc-cleanup.sh
CMD ["/sbin/init"]
