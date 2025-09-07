# CXL to OPML Converter

A PowerShell script that converts CMap Tools concept map files (CXL format) into hierarchical OPML outlines, enabling seamless import into mind mapping and outlining software.

> Want to know the story behind this tool? Read on to discover why it was developed: [When AI Becomes the Curator of Corporate Knowledge: From Transcription to "Vibe Coding"](https://www.linkedin.com/pulse/when-ai-becomes-curator-corporate-knowledge-from-vibe-pancani-ccfaf/)

## Overview

This converter transforms complex concept maps created in [CMap Tools](https://cmap.ihmc.us/) into structured outlines compatible with popular mind mapping applications, note-taking tools, and outline processors.

### Key Features

- **Single File Export**: Convert entire concept map to one OPML file
- **Multi-File Export**: Generate separate OPML files for each concept as root (unique feature)
- **Automatic Root Detection**: Intelligently identifies the main concept
- **Custom Root Selection**: Specify any concept as the hierarchy root
- **Hierarchical Reconstruction**: Converts graph-based relationships into tree structures
- **Metadata Preservation**: Maintains creation dates and titles from original CXL files

## File Format Overview

### CXL Files (CMap Tools Format)

CXL files are XML-based concept maps created by CMap Tools software. They represent knowledge as a **graph structure** with three main components:

#### Structure Components
- **Concepts**: The main ideas or topics (nodes in the graph)
- **Linking Phrases**: Descriptive text that explains relationships
- **Connections**: Directed arrows connecting concepts through linking phrases

#### Relationship Pattern
```
Concept A → Linking Phrase → Concept B
```
Example: `"Plants" → "require" → "Water"`

#### Technical Details
- **Format**: XML with CMap-specific namespaces
- **Encoding**: UTF-8 with Dublin Core metadata
- **Structure**: Non-hierarchical graph allowing multiple parents per concept
- **Complexity**: Single CXL file can contain dozens of interconnected concepts

### OPML Files (Outline Processor Markup Language)

OPML is an XML format designed for hierarchical outlines and is widely supported by:
- Mind mapping software (FreeMind, XMind, MindMeister)
- Note-taking applications (Obsidian, Roam Research)
- RSS readers and content management systems
- Outlining tools (OmniOutliner, Workflowy)

#### Structure
```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Concept Map Title</title>
    <dateCreated>Mon, 07 Sep 2025 14:30:00 GMT</dateCreated>
  </head>
  <body>
    <outline text="Root Concept">
      <outline text="Child Concept 1">
        <outline text="Grandchild Concept" />
      </outline>
      <outline text="Child Concept 2" />
    </outline>
  </body>
</opml>
```

#### Characteristics
- **Hierarchical**: Strict parent-child tree structure
- **Compatibility**: Universally supported across platforms
- **Simplicity**: Clean, readable format
- **Metadata**: Rich header information support

## The Multi-File Export Feature

### Why Multiple OPML Files?

The fundamental challenge in converting CXL to OPML lies in their structural differences:

| Aspect | CXL (Graph) | OPML (Tree) |
|--------|-------------|-------------|
| **Relationships** | Many-to-many | One-to-many |
| **Hierarchy** | Non-hierarchical | Strictly hierarchical |
| **Root Concepts** | Multiple possible | Single root required |
| **Perspectives** | Simultaneous views | Single viewpoint |

### Conversion Challenge

Consider this concept map structure:
```
    Energy ←→ Plants ←→ Water
      ↓       ↓       ↓
   Animals ←→ Food ←→ Nutrients
```

**Problem**: In a graph, `Plants` connects to `Energy`, `Water`, `Animals`, and `Food`. But in a tree structure, `Plants` can only have one parent.

**Solution**: Generate multiple OPML files, each representing a different hierarchical perspective:

1. **Energy_Perspective.opml** - Energy as root
2. **Plants_Perspective.opml** - Plants as root  
3. **Water_Perspective.opml** - Water as root
4. **Animals_Perspective.opml** - Animals as root
5. **Food_Perspective.opml** - Food as root

### Benefits of Multi-File Export

- **Complete Knowledge Capture**: No relationships lost in conversion
- **Multiple Perspectives**: Each concept can serve as a thinking starting point
- **Flexible Import**: Choose the most relevant hierarchy for your current task
- **Comprehensive Analysis**: Compare different conceptual viewpoints
- **Tool Compatibility**: Import the version that works best with your preferred software

## Installation & Requirements

### Prerequisites
- **PowerShell 5.1** or higher
- **Windows, macOS, or Linux** with PowerShell Core
- **Read permissions** for CXL files

### Installation
1. Download the `Convert-CxlToOpml.ps1` script
2. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage Examples

### Basic Conversion
```powershell
# Convert CXL to single OPML file
.\Convert-CxlToOpml.ps1 -SourcePath "MyConceptMap.cxl"
```

### Specify Output Location
```powershell
# Define custom output path
.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -DestinationPath "output.opml"
```

### Custom Root Concept
```powershell
# Use specific concept as hierarchy root
.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -RootConceptId "concept-123"
```

### Multi-File Export (Recommended)
```powershell
# Generate OPML file for each concept perspective
.\Convert-CxlToOpml.ps1 -SourcePath "map.cxl" -ExportAllConcepts
```

## Parameters Reference

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SourcePath` | String | Yes | Path to input CXL file |
| `DestinationPath` | String | No | Output OPML file path |
| `RootConceptId` | String | No | Specific concept ID to use as root |
| `ExportAllConcepts` | Switch | No | Export separate OPML for each concept |

## Output Examples

### Single File Output
```
MyConceptMap.opml
```

### Multi-File Output
```
MyConceptMap_Energy.opml
MyConceptMap_Plants.opml
MyConceptMap_Water.opml
MyConceptMap_Photosynthesis.opml
MyConceptMap_Ecosystem.opml
```

## Supported Applications

The generated OPML files work with:

### Mind Mapping Software
- FreeMind
- XMind

## Technical Implementation

### Root Concept Detection
The script uses intelligent algorithms to identify root concepts:

1. **No Incoming Connections**: Concepts that aren't targets of any relationships
2. **Name Pattern Matching**: Looks for concepts containing "root", "main", or "center"
3. **User Override**: Respects explicitly specified root concept IDs
4. **Fallback Strategy**: Uses first concept if no clear root exists

### Hierarchy Construction
```
CXL: Concept A → Linking Phrase → Concept B
OPML: Concept A (parent) → Concept B (child)
```

The converter traces through linking phrases to establish direct parent-child relationships, effectively "flattening" the graph into tree structures.

### File Naming Convention
```
{OriginalFileName}_{SanitizedConceptLabel}.opml
```

Invalid filename characters are automatically replaced with underscores, and names are truncated to prevent path length issues.

## Troubleshooting

### Common Issues

**Error: "No concepts found in the CXL file"**
- Verify the CXL file is not corrupted
- Check file encoding (should be UTF-8)
- Ensure file was saved properly from CMap Tools

**Warning: "No clear root concept found"**
- Normal for highly interconnected maps
- Script will use first concept as root
- Consider using `-RootConceptId` parameter

**File naming issues**
- Script automatically sanitizes invalid characters
- Long concept names are truncated to 100 characters
- Special characters replaced with underscores

### Performance Notes
- Large concept maps (100+ concepts) may take several seconds to process
- Multi-file export time scales linearly with concept count
- Memory usage is generally minimal

## Contributing

Contributions are welcome! Areas for improvement:
- Support for additional CMap Tools features
- Enhanced metadata preservation
- Alternative export formats
- Performance optimizations
- Cross-platform testing

## License

This script is provided as-is for educational and personal use. Please respect CMap Tools licensing terms when working with CXL files.

---

*Convert your concept maps into versatile outlines and unlock new possibilities for knowledge organization and sharing.*