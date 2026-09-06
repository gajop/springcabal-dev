#!/bin/bash

curl -L --output spring-linux.7z https://github.com/beyond-all-reason/RecoilEngine/releases/download/2025.01.6/spring_bar_.rel2501.2025.01.6_linux-64-minimal-portable.7z

# Extract engine if needed
if [ ! -d "spring-linux" ]; then
    7z x spring-linux.7z
fi

# Copy custom Spring settings (preserves detail rendering settings after engine updates)
cp springsettings-custom.cfg spring-linux/springsettings.cfg

git clone --recursive https://github.com/SpringCabal/Hunted.git spring-linux/games/Hunted.sdd
git clone --recursive git@github.com:SpringCabal/Hunted-Map.git spring-linux/maps/HuntedMap.sdd

git clone --recursive git@github.com:SpringCabal/Area-17.git spring-linux/games/Area-17.sdd
git clone --recursive git@github.com:SpringCabal/Area-17-Map.git spring-linux/maps/Area17Map.sdd

# To the Last Drop
git clone --recursive git@github.com:SpringCabal/LD43.git spring-linux/games/LD43.sdd
git clone --recursive git@github.com:SpringCabal/LD43-map.git spring-linux/maps/LD43-map.sdd

git clone --recursive git@github.com:SpringCabal/Gravitas.git spring-linux/games/Gravitas.sdd
git clone --recursive git@github.com:SpringCabal/Gravitas-map.git spring-linux/maps/Gravitas-map.sdd
# TODO: SBC, SBC-Gravitas, projectcs/GravitasEnterprise

# My Cube
git clone --recursive git@github.com:SpringCabal/LD42.git spring-linux/games/LD42.sdd

git clone --recursive git@github.com:SpringCabal/Flove.git spring-linux/games/Flove.sdd
git clone --recursive git@github.com:SpringCabal/LD34-map.git spring-linux/maps/LD34-map.sdd

# Parts needed
git clone --recursive git@github.com:SpringCabal/LD35-map.git spring-linux/maps/LD35-map.sdd