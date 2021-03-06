#!/bin/bash -xe

source ${P}

if [ -f /quickstart/pre-install.sh ]
then
  /quickstart/pre-install.sh
fi

qs_enable_epel &> /var/log/userdata.qs_enable_epel.log || true

if [ -z ${LOCAL_REPO_HOST_IP} ]; then 
  qs_retry_command 25 aws s3 cp ${QS_S3URI}scripts/redhat_ose-register-${OCP_VERSION}.sh ~/redhat_ose-register.sh
  chmod 755 ~/redhat_ose-register.sh
  qs_retry_command 25 ~/redhat_ose-register.sh ${RH_USER} ${RH_PASS} ${RH_POOLID}
else 
  qs_retry_command 25 aws s3 cp ${QS_S3URI}scripts/yum.repos.d/ose.repo /etc/yum.repos.d/ose.repo
  sed -ie "s/<server_IP>/${LOCAL_REPO_HOST_IP}/g" /etc/yum.repos.d/ose.repo
  rm /etc/yum.repos.d/ose.repoe
  curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
  rm -fr /var/cache/yum/*
  yum clean all
fi

mkdir -p /etc/aws/
printf "[Global]\nZone = $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)\n" > /etc/aws/aws.conf
printf "KubernetesClusterTag='kubernetes.io/cluster/${AWS_STACKNAME}-${AWS_REGION}'\n" >> /etc/aws/aws.conf
printf "KubernetesClusterID=owned\n" >> /etc/aws/aws.conf

if [ "${LAUNCH_CONFIG}" != "OpenShiftEtcdLaunchConfig" ]; then
    if [ "${OCP_VERSION}" != "3.9" ] ; then
        qs_retry_command 10 yum install docker-client-1.13.1 docker-common-1.13.1 docker-rhel-push-plugin-1.13.1 docker-1.13.1 -y
    else
        qs_retry_command 10 yum install docker-client-1.12.6 docker-common-1.12.6 docker-rhel-push-plugin-1.12.6 docker-1.12.6 -y
    fi
    systemctl enable docker.service
    qs_retry_command 20 'systemctl start docker.service'
    echo "CONTAINER_THINPOOL=docker-pool" >> /etc/sysconfig/docker-storage-setup
    echo "DEVS=/dev/xvdb" >> /etc/sysconfig/docker-storage-setup
    echo "VG=docker-vg" >>/etc/sysconfig/docker-storage-setup
    echo "STORAGE_DRIVER=devicemapper" >> /etc/sysconfig/docker-storage-setup
    systemctl stop docker
    rm -rf /var/lib/docker
    docker-storage-setup
    systemctl start docker
fi

qs_retry_command 10 cfn-init -v  --stack ${AWS_STACKNAME} --resource ${LAUNCH_CONFIG} --configsets quickstart --region ${AWS_REGION}
qs_retry_command 10 yum install -y wget atomic-openshift-docker-excluder atomic-openshift-node \
    atomic-openshift-sdn-ovs ceph-common conntrack-tools dnsmasq glusterfs \
    glusterfs-client-xlators glusterfs-fuse glusterfs-libs iptables-services \
    iscsi-initiator-utils iscsi-initiator-utils-iscsiuio tuned-profiles-atomic-openshift-node

systemctl restart dbus
systemctl restart dnsmasq
qs_retry_command 25 ls /var/run/dbus/system_bus_socket
systemctl restart NetworkManager
systemctl restart systemd-logind

cd /tmp
qs_retry_command 10 wget https://aws-quickstart-cn.s3.cn-northwest-1.amazonaws.com.cn/aws-ssm-agent/amazon-ssm-agent.rpm
qs_retry_command 10 yum install -y ./amazon-ssm-agent.rpm
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent
rm ./amazon-ssm-agent.rpm

if [ -f /quickstart/post-install.sh ]
then
  /quickstart/post-install.sh
fi
