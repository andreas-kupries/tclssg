# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Commands that can be given to Tclssg on the command line.
namespace eval ::tclssg::command {
    namespace export *
    namespace ensemble create \
            -prefixes 0 \
            -unknown ::tclssg::command::unknown

    proc init {inputDir outputDir {debugDir {}} {options {}}} {
        foreach dir [
            list $::tclssg::config(contentDirName) \
                 $::tclssg::config(templateDirName) \
                 $::tclssg::config(staticDirName) \
                 [file join $::tclssg::config(contentDirName) blog]
        ] {
            file mkdir [file join $inputDir $dir]
        }
        file mkdir $outputDir

        # Copy project skeleton.
        set skipRegExp [
            if {"templates" in $options} {
                lindex {}
            } else {
                lindex {.*templates.*}
            }
        ]
        ::tclssg::utils::copy-files \
                $::tclssg::config(skeletonDir) $inputDir 0 $skipRegExp
    }

    proc build {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [::tclssg::load-config $inputDir]

        if {"debug" in $options} {
            tclssg debugger enable
        }

        if {[file isdir $inputDir]} {
            ::tclssg::compile-website $inputDir $outputDir $debugDir \
                    $websiteConfig
        } else {
            error "couldn't access directory \"$inputDir\""
        }
    }

    proc clean {inputDir outputDir {debugDir {}} {options {}}} {
        foreach file [::fileutil::find $outputDir {file isfile}] {
            puts "deleting $file"
            file delete $file
        }
    }

    proc update {inputDir outputDir {debugDir {}} {options {}}} {
        set updateSourceDirs [
            list $::tclssg::config(staticDirName) {static files}
        ]
        if {"templates" in $options} {
            lappend updateSourceDirs \
                    $::tclssg::config(templateDirName) \
                    templates
        }
        if {"yes" in $options} {
            set overwriteMode 1
        } else {
            set overwriteMode 2
        }
        foreach {dir descr} $updateSourceDirs {
            puts "updating $descr"
            ::tclssg::utils::copy-files [
                file join $::tclssg::config(skeletonDir) $dir
            ] [
                file join $inputDir $dir
            ] $overwriteMode
        }
    }

    proc deploy-copy {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [::tclssg::load-config $inputDir]

        set deployDest [dict get $websiteConfig deployCopy path]

        ::tclssg::utils::copy-files $outputDir $deployDest 1
    }

    proc deploy-custom {inputDir outputDir {debugDir {}} {options {}}} {
        proc exec-deploy-command {key} {
            foreach varName {deployCustomCommand outputDir file fileRel} {
                upvar 1 $varName $varName
            }
            if {[dict exists $deployCustomCommand $key] &&
                ([dict get $deployCustomCommand $key] ne "")} {
                set preparedCommand [subst -nocommands \
                        [dict get $deployCustomCommand $key]]
                set exitStatus 0
                set error [catch \
                        {set output \
                            [exec -ignorestderr -- {*}$preparedCommand]}\
                        _ \
                        options]
                if {$error} {
                    set details [dict get $options -errorcode]
                    if {[lindex $details 0] eq "CHILDSTATUS"} {
                        set exitStatus [lindex $details 2]
                    } else {
                        error [dict get $options -errorinfo]
                    }
                }
                if {$exitStatus == 0} {
                    if {$output ne ""} {
                        puts $output
                    }
                } else {
                    puts "command '$preparedCommand' returned exit code\
                            $exitStatus."
                }
            }
        }
        set websiteConfig [::tclssg::load-config $inputDir]

        set deployCustomCommand \
                [dict get $websiteConfig deployCustomCommand]

        puts "deploying..."
        exec-deploy-command start
        foreach file [::fileutil::find $outputDir {file isfile}] {
            set fileRel [::fileutil::relative $outputDir $file]
            exec-deploy-command file
        }
        exec-deploy-command end
        puts "done."
    }

    proc deploy-ftp {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [::tclssg::load-config $inputDir]

        package require ftp
        global errorInfo
        set conn [
            ::ftp::Open \
                    [dict get $websiteConfig deployFtp server] \
                    [dict get $websiteConfig deployFtp user] \
                    [dict get $websiteConfig deployFtp password] \
                    -port [::tclssg::utils::dict-default-get 21 \
                            $websiteConfig deployFtp port] \
                    -mode passive
        ]
        set deployFtpPath [dict get $websiteConfig deployFtp path]

        ::ftp::Type $conn binary

        foreach file [::fileutil::find $outputDir {file isfile}] {
            set destFile [::tclssg::utils::replace-path-root \
                    $file $outputDir $deployFtpPath]
            set path [file split [file dirname $destFile]]
            set partialPath {}

            foreach dir $path {
                set partialPath [file join $partialPath $dir]
                if {[::ftp::Cd $conn $partialPath]} {
                    ::ftp::Cd $conn /
                } else {
                    puts "creating directory $partialPath"
                    ::ftp::MkDir $conn $partialPath
                }
            }
            puts "uploading $file as $destFile"
            if {![::ftp::Put $conn $file $destFile]} {
                error "upload error: $errorInfo"
            }
        }
        ::ftp::Close $conn
    }

    proc open {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [::tclssg::load-config $inputDir]

        package require browse
        ::browse::url [
            file rootname [
                file join $outputDir [
                    ::tclssg::utils::dict-default-get index.md \
                            $websiteConfig indexPage
                ]
            ]
        ].html
    }

    proc version {inputDir outputDir {debugDir {}} {options {}}} {
        puts $::tclssg::config(version)
    }

    proc help {{inputDir ""} {outputDir ""} {debugDir ""} {options ""}} {
        global argv0

        # Format: {command description {option optionDescription ...} ...}.
        set commandHelp [list {*}{
            init {create a new project by cloning the default project\
                    skeleton} {
                --templates {copy template files from the project skeleton\
                        to inputDir}
            }
            build {build the static website} {
                --debug {dump the results of intermediate stages of content\
                    processing to disk}
            }
            clean {delete all files in outputDir} {}
            update {update the inputDir for a new version of Tclssg by\
                    copying the static files (e.g., CSS) of the project\
                    skeleton over the static files in inputDir and having\
                    the user confirm replacement} {
                --templates {*also* copy the templates of the project\
                        skeleton over the templates in inputDir}
                --yes       {assume the answer to all questions to be "yes"\
                        (replace all)}
            }
            deploy-copy {copy the output to the file system path set\
                    in the config file} {}
            deploy-custom {run the custom deployment commands specified in\
                    the config file on the output} {}
            deploy-ftp  {upload the output to the FTP server set in the\
                    config file} {}
            open {open the index page in the default web browser} {}
            version {print the version number and exit} {}
            help {show this message}
        }]

        set commandHelpText {}
        foreach {command description options} $commandHelp {
            append commandHelpText \
                    [::tclssg::utils::text-columns \
                            "" 4 \
                            $command 15 \
                            $description 43]
            foreach {option optionDescr} $options {
                append commandHelpText \
                        [::tclssg::utils::text-columns \
                                "" 8 \
                                $option 12 \
                                $optionDescr 42]
            }
        }

        puts [format [
                ::tclssg::utils::trim-indentation {
                    usage: %s <command> [options] [inputDir [outputDir]]

                    Possible commands are:
                    %s

                    inputDir defaults to "%s"
                    outputDir defaults to "%s"
                }
            ] \
            $argv0 \
            $commandHelpText \
            $::tclssg::config(defaultInputDir) \
            $::tclssg::config(defaultOutputDir)]
    }

    proc unknown args {
        return ::tclssg::command::help
    }
} ;# namespace command
