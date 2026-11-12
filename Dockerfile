FROM bioconductor/bioconductor_docker:devel

COPY . /tmp/fbrglm

RUN R -e "install.packages('remotes'); \
    remotes::install_local('/tmp/fbrglm', \
    upgrade='always', force=TRUE, INSTALL_opts = '--install-tests', \
    dependencies = TRUE); \
    tools::testInstalledPackage('fbrglm')"
