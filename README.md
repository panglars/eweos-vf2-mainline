# eweOS for visionfive2 mainline image

Build script to create the eweOS Linux image for [StarFive VisionFive 2](https://doc-en.rvspace.org/Doc_Center/visionfive_2.html).

Use mainline linux kernel,u-boot,opensbi.See the [upstream status](https://rvspace.org/en/project/JH7110_Upstream_Plan).
## Usage

``` shell
sudo ./build.sh

sudo dd if=ewe-vf2.img of=/dev/<your-device> bs=1M status=progress
```

## Credit

- [cwt-vf2/archlinux-image-vf2](https://github.com/cwt-vf2/archlinux-image-vf2)
- [eweOS](https://os.ewe.moe)
