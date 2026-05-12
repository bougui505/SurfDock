import os
import shutil
import pandas as pd
from rdkit import Chem
from rdkit.Chem import AllChem
import argparse

def create_dummy_ligand(coords, output_path):
    """Creates a dummy methane molecule at the specified coordinates to define the pocket."""
    mol = Chem.MolFromSmiles('C')
    mol = Chem.AddHs(mol)
    # Give it some 3D structure first
    AllChem.EmbedMolecule(mol, AllChem.ETKDG())
    conf = mol.GetConformer()
    
    # Translate to the target coordinates
    x, y, z = map(float, coords.split(','))
    curr_center = Chem.rdMolTransforms.ComputeCentroid(conf)
    for i in range(mol.GetNumAtoms()):
        pos = conf.GetAtomPosition(i)
        conf.SetAtomPosition(i, (pos.x - curr_center.x + x, pos.y - curr_center.y + y, pos.z - curr_center.z + z))
    
    writer = Chem.SDWriter(output_path)
    writer.write(mol)
    writer.close()

def smi_to_sdf(smi_path, sdf_path):
    """Converts a SMI file to a multi-molecule SDF file."""
    # Try to read as SMILES, assuming one SMILES per line
    with open(smi_path, 'r') as f:
        smiles_list = [line.strip().split()[0] for line in f if line.strip()]
    
    writer = Chem.SDWriter(sdf_path)
    count = 0
    for smi in smiles_list:
        mol = Chem.MolFromSmiles(smi)
        if mol:
            # Add a basic 3D conformer so SurfDock can process it
            mol = Chem.AddHs(mol)
            AllChem.EmbedMolecule(mol, AllChem.ETKDG())
            mol.SetProp("_Name", f"ligand_{count}")
            writer.write(mol)
            count += 1
    writer.close()
    return count

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--protein', type=str, required=True, help='Path to protein PDB')
    parser.add_argument('--ligands', type=str, required=True, help='Path to SMI file')
    parser.add_argument('--pocket_center', type=str, help='x,y,z coordinates of the pocket center')
    parser.add_argument('--out_dir', type=str, required=True, help='Output directory')
    args = parser.parse_args()

    target_name = "custom_target"
    data_dir = os.path.join(args.out_dir, "data")
    target_dir = os.path.join(data_dir, target_name)
    os.makedirs(target_dir, exist_ok=True)

    # 1. Prepare Protein
    # The pipeline expects {target_name}_protein_processed.pdb
    shutil.copy(args.protein, os.path.join(target_dir, f"{target_name}_protein_processed.pdb"))

    # 2. Prepare Ligands
    library_sdf = os.path.join(target_dir, "library.sdf")
    num_mols = smi_to_sdf(args.ligands, library_sdf)
    print(f"Converted {num_mols} molecules to SDF.")

    # 3. Prepare Pocket Reference (Needed for surface extraction)
    ref_ligand = os.path.join(target_dir, f"{target_name}_ligand.sdf")
    if args.pocket_center:
        create_dummy_ligand(args.pocket_center, ref_ligand)
        print(f"Created dummy pocket reference at {args.pocket_center}")
    else:
        print("Error: pocket_center is required to define the screening site.")
        exit(1)

    print(f"Custom screening setup complete in {args.out_dir}")
    print(f"You can now run the screening pipeline using {data_dir} as DATA_DIR.")
