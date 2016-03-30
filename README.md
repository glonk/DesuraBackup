# DesuraBackup
Back up your virtual belongings on your Desura account before its too late. 

This tool was devised to access Desuras API and download all available content you own onto your computer as a backup. It specifically loads the [MCF Files] used by the DesuraClient to install its content. There are plans to create a local webservice to allow game managment with the [Desurium Client] using those [MCF Files] as content supply.

The tool is fully automated and has resume support and hence can be interrupted at any time. You only need to supply your login credencials into the **login.yml** file.

You might need to apply DNS modifications too depending on you can actually reach Desuras servers.

Read further: on [Reddit]

## Requirements for building the source
* Linux-based OS
* Windows-based OS
* Mac-based OS (currently unsupported but should work)
* a recent installation of Perl 5.12+
* expat-devel headers (libexpat-dev)

## Building
Pull the source and get CPAN up and install dependencies

* HTTP::Tiny
* HTTP::Tiny::Multipart
* HTTP::CookieJar
* File::Slurp
* YAML::Any
* XML::Twig
* URI::Escape

## See also
[DesuraDumper] - with support for fetching Installers & Keys (Windows-only)

[DesuraDumper]: https://github.com/GMMan/DesuraDump
[Reddit]: https://www.reddit.com/r/GameDealsMeta/comments/4bksoi/emergency_desura_collection_dumper_update/
[MCF Files]: https://github.com/desura/desura-app/wiki/MCFFileFormat
[Desurium Client]: https://github.com/desura/desura-app
