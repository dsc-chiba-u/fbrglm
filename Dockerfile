FROM bioconductor/bioconductor_docker:devel

RUN R -e "install.packages('remotes'); \
    remotes::install_github('dsc-chiba-u/fbrglm', \
    upgrade='always', force=TRUE, INSTALL_opts = '--install-tests'); \
    tools::testInstalledPackage('fbrglm')"
