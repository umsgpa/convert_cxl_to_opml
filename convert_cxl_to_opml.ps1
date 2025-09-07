# Requires -Version 5.1
# © 2025 Gabriele PANCANI


#### Basic usage - convert CXL to OPML
###.\Convert-CxlToOpml.ps1 -SourcePath "C:\path\to\your\map.cxl"
###
#### Specify output location
###.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -DestinationPath "output.opml"
###
#### Specify a specific root concept by ID
###.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -RootConceptId "your-concept-id"
###
#### Export all concepts as separate OPML files
###.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -ExportAllConcepts

function Convert-CxlToOpml {
    <#
   .SYNOPSIS
        Converts a CMap CXL concept map file to a hierarchical OPML file.
   .DESCRIPTION
        This script takes a CXL file as input, parses its concept map structure,
        and generates a new OPML XML file. It reconstructs the hierarchical
        relationships from CXL propositions (Concept - Linking Phrase - Concept)
        back into parent-child outline structure suitable for mind mapping software.
   .PARAMETER SourcePath
        The full path to the source .cxl file.
   .PARAMETER DestinationPath
        The full path for the output .opml file. If not specified, the script will
        create an .opml file in the same directory as the source.
   .PARAMETER RootConceptId
        The ID of the concept to use as the root. If not specified, the script
        will attempt to find the most suitable root concept automatically.
        Ignored when -ExportAllConcepts is used.
   .PARAMETER ExportAllConcepts
        When used, the script exports one OPML file for each concept in the concept-list.
        Each file is named using the pattern: OriginalFileName_ConceptLabel.opml
    #>
   
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [string]$DestinationPath,

        [string]$RootConceptId,

        [switch]$ExportAllConcepts
    )

    # Helper class to represent concept relationships
    class ConceptNode {
        [string]$Id
        [string]$Label
        [System.Collections.Generic.List[ConceptNode]]$Children
        [ConceptNode]$Parent
        [int]$Level
        
        ConceptNode([string]$id, [string]$label) {
            $this.Id = $id
            $this.Label = $label
            $this.Children = New-Object 'System.Collections.Generic.List[ConceptNode]'
            $this.Level = 0
        }
        
        [void] AddChild([ConceptNode]$child) {
            $this.Children.Add($child)
            $child.Parent = $this
            $child.Level = $this.Level + 1
        }
    }

    # Function to sanitize filename by removing/replacing invalid characters
    function Sanitize-FileName {
        param(
            [string]$FileName
        )
        
        # Define invalid characters for Windows file names
        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
        
        # Replace invalid characters with underscore
        $sanitized = $FileName
        foreach ($char in $invalidChars) {
            $sanitized = $sanitized.Replace($char, '_')
        }
        
        # Additional replacements for common problematic characters
        $sanitized = $sanitized -replace '\s+', '_'  # Replace multiple spaces with single underscore
        $sanitized = $sanitized -replace '_+', '_'   # Replace multiple underscores with single underscore
        $sanitized = $sanitized.Trim('_')            # Remove leading/trailing underscores
        
        # Ensure filename is not empty and not too long
        if ([string]::IsNullOrWhiteSpace($sanitized)) {
            $sanitized = "Concept"
        }
        
        # Limit length to 100 characters to avoid path length issues
        if ($sanitized.Length -gt 100) {
            $sanitized = $sanitized.Substring(0, 100).TrimEnd('_')
        }
        
        return $sanitized
    }

    # Function to generate output file path based on concept
    function Get-ConceptOutputPath {
        param(
            [string]$SourceFilePath,
            [string]$ConceptLabel,
            [string]$BaseDestinationPath = $null
        )
        
        $sourceFileInfo = Get-Item $SourceFilePath
        $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFileInfo.Name)
        $sanitizedLabel = Sanitize-FileName -FileName $ConceptLabel
        
        if ($BaseDestinationPath) {
            $destinationDir = [System.IO.Path]::GetDirectoryName($BaseDestinationPath)
        } else {
            $destinationDir = $sourceFileInfo.DirectoryName
        }
        
        $outputFileName = "${baseFileName}_${sanitizedLabel}.opml"
        return Join-Path $destinationDir $outputFileName
    }

    # Function to find the root concept (concept with no incoming connections or specified root)
    function Find-RootConcept {
        param(
            $Concepts,
            $Connections,
            [string]$SpecifiedRootId
        )
        
        if ($SpecifiedRootId) {
            $specifiedRoot = $Concepts | Where-Object { $_.id -eq $SpecifiedRootId }
            if ($specifiedRoot) {
                Write-Host "Using specified root concept: $($specifiedRoot.label)"
                return $specifiedRoot.id
            }
            else {
                Write-Warning "Specified root concept ID '$SpecifiedRootId' not found. Auto-detecting root."
            }
        }
        
        # Find concepts that are never the target of connections (potential roots)
        $allTargetIds = @()
        foreach ($connection in $Connections) {
            $allTargetIds += $connection.'to-id'
        }
        
        $rootCandidates = @()
        foreach ($concept in $Concepts) {
            if ($concept.id -notin $allTargetIds) {
                $rootCandidates += $concept
            }
        }
        
        if ($rootCandidates.Count -eq 1) {
            Write-Host "Found root concept: $($rootCandidates[0].label)"
            return $rootCandidates[0].id
        }
        elseif ($rootCandidates.Count -gt 1) {
            # If multiple candidates, pick the first one or one with "root" in name
            $preferredRoot = $rootCandidates | Where-Object { $_.label -match "root|main|center" } | Select-Object -First 1
            if ($preferredRoot) {
                Write-Host "Found preferred root concept: $($preferredRoot.label)"
                return $preferredRoot.id
            }
            else {
                Write-Host "Multiple root candidates found. Using: $($rootCandidates[0].label)"
                return $rootCandidates[0].id
            }
        }
        else {
            # No clear root found, use the first concept
            Write-Warning "No clear root concept found. Using first concept: $($Concepts[0].label)"
            return $Concepts[0].id
        }
    }

    # Function to build the concept tree from CXL connections
    function Build-ConceptTree {
        param(
            $Concepts,
            $LinkingPhrases,
            $Connections,
            [string]$RootId
        )
        
        # Create a hashtable for quick concept lookup
        $conceptLookup = @{}
        foreach ($concept in $Concepts) {
            $conceptLookup[$concept.id] = [ConceptNode]::new($concept.id, $concept.label)
        }
        
        # Build parent-child relationships from connections
        # CXL structure: Concept -> LinkingPhrase -> Concept
        # We need to trace through linking phrases to find concept-to-concept relationships
        
        $linkingPhraseLookup = @{}
        foreach ($linkingPhrase in $LinkingPhrases) {
            $linkingPhraseLookup[$linkingPhrase.id] = $linkingPhrase
        }
        
        # Group connections by their from-id to find paths
        $connectionsFromLookup = @{}
        foreach ($connection in $Connections) {
            $fromId = $connection.'from-id'
            if (-not $connectionsFromLookup.ContainsKey($fromId)) {
                $connectionsFromLookup[$fromId] = @()
            }
            $connectionsFromLookup[$fromId] += $connection
        }
        
        # Find concept-to-concept relationships via linking phrases
        foreach ($concept in $Concepts) {
            $conceptId = $concept.id
            
            # Find connections from this concept
            if ($connectionsFromLookup.ContainsKey($conceptId)) {
                foreach ($connection in $connectionsFromLookup[$conceptId]) {
                    $linkingPhraseId = $connection.'to-id'
                    
                    # Check if this connection goes to a linking phrase
                    if ($linkingPhraseLookup.ContainsKey($linkingPhraseId)) {
                        # Find connections from this linking phrase to other concepts
                        if ($connectionsFromLookup.ContainsKey($linkingPhraseId)) {
                            foreach ($lpConnection in $connectionsFromLookup[$linkingPhraseId]) {
                                $childConceptId = $lpConnection.'to-id'
                                
                                # Verify the target is indeed a concept
                                if ($conceptLookup.ContainsKey($childConceptId)) {
                                    # Establish parent-child relationship
                                    $parentNode = $conceptLookup[$conceptId]
                                    $childNode = $conceptLookup[$childConceptId]
                                    $parentNode.AddChild($childNode)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return $conceptLookup[$RootId]
    }

    # Recursive function to convert concept tree to OPML outline structure
    function Convert-ConceptToOpml {
        param(
            [ConceptNode]$ConceptNode,
            $OpmlDocument,
            $ParentElement
        )
        
        # Create outline element for this concept
        $outlineElement = $OpmlDocument.CreateElement('outline')
        $outlineElement.SetAttribute('text', $ConceptNode.Label)
        
        # Add any additional attributes that might be useful
        $outlineElement.SetAttribute('type', 'concept')
        
        $ParentElement.AppendChild($outlineElement)
        
        # Process children recursively
        foreach ($child in $ConceptNode.Children) {
            Convert-ConceptToOpml -ConceptNode $child -OpmlDocument $OpmlDocument -ParentElement $outlineElement
        }
    }

    # Function to create OPML metadata
    function Add-OpmlMetadata {
        param(
            $OpmlDocument,
            $HeadElement,
            $CxlMetadata,
            $ConceptLabel = $null
        )
        
        # Extract title from CXL metadata or use default
        $titleElement = $OpmlDocument.CreateElement('title')
        $titleText = if ($ConceptLabel) { "Concept Map: $ConceptLabel" } else { "Converted from CXL" }
        
        if ($CxlMetadata) {
            $dcTitle = $CxlMetadata.SelectSingleNode("//dc:title", $namespaceManager)
            if ($dcTitle -and $dcTitle.InnerText) {
                $titleText = if ($ConceptLabel) { "$($dcTitle.InnerText) - $ConceptLabel" } else { $dcTitle.InnerText }
            }
        }
        
        $titleElement.InnerText = $titleText
        $HeadElement.AppendChild($titleElement)
        
        # Add other metadata
        $dateCreatedElement = $OpmlDocument.CreateElement('dateCreated')
        $dateCreatedElement.InnerText = (Get-Date -Format "ddd, dd MMM yyyy HH:mm:ss") + " GMT"
        $HeadElement.AppendChild($dateCreatedElement)
        
        $dateModifiedElement = $OpmlDocument.CreateElement('dateModified')
        $dateModifiedElement.InnerText = (Get-Date -Format "ddd, dd MMM yyyy HH:mm:ss") + " GMT"
        $HeadElement.AppendChild($dateModifiedElement)
        
        $ownerNameElement = $OpmlDocument.CreateElement('ownerName')
        $ownerNameElement.InnerText = 'PowerShell CXL to OPML Converter'
        $HeadElement.AppendChild($ownerNameElement)
        
        $expansionStateElement = $OpmlDocument.CreateElement('expansionState')
        $expansionStateElement.InnerText = '1'
        $HeadElement.AppendChild($expansionStateElement)
        
        $vertScrollStateElement = $OpmlDocument.CreateElement('vertScrollState')
        $vertScrollStateElement.InnerText = '1'
        $HeadElement.AppendChild($vertScrollStateElement)
        
        $windowTopElement = $OpmlDocument.CreateElement('windowTop')
        $windowTopElement.InnerText = '61'
        $HeadElement.AppendChild($windowTopElement)
        
        $windowLeftElement = $OpmlDocument.CreateElement('windowLeft')
        $windowLeftElement.InnerText = '304'
        $HeadElement.AppendChild($windowLeftElement)
        
        $windowBottomElement = $OpmlDocument.CreateElement('windowBottom')
        $windowBottomElement.InnerText = '562'
        $HeadElement.AppendChild($windowBottomElement)
        
        $windowRightElement = $OpmlDocument.CreateElement('windowRight')
        $windowRightElement.InnerText = '842'
        $HeadElement.AppendChild($windowRightElement)
    }

    # Function to create a single OPML file for a specific root concept
    function Create-OpmlFile {
        param(
            $Concepts,
            $LinkingPhrases,
            $Connections,
            $Metadata,
            [string]$RootConceptId,
            [string]$OutputPath,
            [string]$ConceptLabel = $null
        )

        # Build the concept tree
        $rootNode = Build-ConceptTree -Concepts $Concepts -LinkingPhrases $LinkingPhrases -Connections $Connections -RootId $RootConceptId

        if (-not $rootNode) {
            Write-Warning "Failed to build concept tree for concept ID: $RootConceptId"
            return $false
        }

        # Initialize the new OPML XmlDocument object
        $opmlDocument = New-Object System.Xml.XmlDocument
        $declaration = $opmlDocument.CreateXmlDeclaration('1.0', 'UTF-8', $null)
        $opmlDocument.AppendChild($declaration)

        # Create the root <opml> element
        $opmlRoot = $opmlDocument.CreateElement('opml')
        $opmlRoot.SetAttribute('version', '2.0')
        $opmlDocument.AppendChild($opmlRoot)

        # Create the <head> section
        $headElement = $opmlDocument.CreateElement('head')
        $opmlRoot.AppendChild($headElement)

        # Add metadata to head
        Add-OpmlMetadata -OpmlDocument $opmlDocument -HeadElement $headElement -CxlMetadata $Metadata -ConceptLabel $ConceptLabel

        # Create the <body> section
        $bodyElement = $opmlDocument.CreateElement('body')
        $opmlRoot.AppendChild($bodyElement)

        # Convert the concept tree to OPML outline structure
        if ($rootNode.Children.Count -gt 0) {
            # Include root as top-level outline
            Convert-ConceptToOpml -ConceptNode $rootNode -OpmlDocument $opmlDocument -ParentElement $bodyElement
        }
        else {
            # Root has no children, just add it as a single outline item
            Convert-ConceptToOpml -ConceptNode $rootNode -OpmlDocument $opmlDocument -ParentElement $bodyElement
        }

        # Save the OPML document
        try {
            $opmlDocument.Save($OutputPath)
            Write-Host "Successfully created OPML file: $OutputPath"
            Write-Host "  Root concept: $($rootNode.Label)"
            Write-Host "  Outline items: $(($bodyElement.SelectNodes('.//outline')).Count)"
            return $true
        }
        catch {
            Write-Error "Failed to save OPML file '$OutputPath': $($_.Exception.Message)"
            return $false
        }
    }

    # --- Main Script Body ---

    Write-Host "Starting conversion from CXL to OPML..."

    # Validate source file path
    $resolvedSourcePath = Resolve-Path -Path $SourcePath -ErrorAction Stop
    Write-Host "Found source file: $resolvedSourcePath"

    # Load the CXL file into a PowerShell XML object
    try {
        [xml]$cxlXml = Get-Content -Path $resolvedSourcePath.Path -Raw -Encoding UTF8
    }
    catch {
        Write-Error "Failed to load CXL file. Ensure it is a valid XML document."
        return
    }

    # Set up namespace manager for CXL namespaces
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($cxlXml.NameTable)
    $namespaceManager.AddNamespace("cmap", "http://cmap.ihmc.us/xml/cmap/")
    $namespaceManager.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")
    $namespaceManager.AddNamespace("dcterms", "http://purl.org/dc/terms/")

    # Extract concepts, linking phrases, and connections from CXL
    $concepts = $cxlXml.SelectNodes("//cmap:concept", $namespaceManager)
    $linkingPhrases = $cxlXml.SelectNodes("//cmap:linking-phrase", $namespaceManager)
    $connections = $cxlXml.SelectNodes("//cmap:connection", $namespaceManager)
    $metadata = $cxlXml.SelectSingleNode("//cmap:res-meta", $namespaceManager)

    Write-Host "Found $($concepts.Count) concepts, $($linkingPhrases.Count) linking phrases, and $($connections.Count) connections"

    if ($concepts.Count -eq 0) {
        Write-Error "No concepts found in the CXL file."
        return
    }

    if ($ExportAllConcepts) {
        Write-Host "Exporting all concepts as separate OPML files..."
        
        $successCount = 0
        $failCount = 0
        
        foreach ($concept in $concepts) {
            $conceptId = $concept.id
            $conceptLabel = $concept.label
            
            Write-Host "`nProcessing concept: '$conceptLabel' (ID: $conceptId)"
            
            # Generate output path for this concept
            $outputPath = Get-ConceptOutputPath -SourceFilePath $resolvedSourcePath.Path -ConceptLabel $conceptLabel -BaseDestinationPath $DestinationPath
            
            # Create OPML file for this concept
            $success = Create-OpmlFile -Concepts $concepts -LinkingPhrases $linkingPhrases -Connections $connections -Metadata $metadata -RootConceptId $conceptId -OutputPath $outputPath -ConceptLabel $conceptLabel
            
            if ($success) {
                $successCount++
            } else {
                $failCount++
            }
        }
        
        Write-Host "`nExport completed:"
        Write-Host "  Successfully exported: $successCount files"
        Write-Host "  Failed exports: $failCount files"
    }
    else {
        # Single file export (original behavior)
        
        # Define destination path if not provided
        if (-not $DestinationPath) {
            $DestinationPath = [System.IO.Path]::ChangeExtension($resolvedSourcePath.Path, '.opml')
        }
        Write-Host "Destination file will be: $DestinationPath"

        # Find the root concept
        $rootConceptId = Find-RootConcept -Concepts $concepts -Connections $connections -SpecifiedRootId $RootConceptId

        # Create single OPML file
        $success = Create-OpmlFile -Concepts $concepts -LinkingPhrases $linkingPhrases -Connections $connections -Metadata $metadata -RootConceptId $rootConceptId -OutputPath $DestinationPath
        
        if (-not $success) {
            Write-Error "Failed to create OPML file."
        }
    }
}

# Call the function with the provided parameters
Convert-CxlToOpml @args