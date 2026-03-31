import gmsh
import numpy as np

class Generator:
    def __init__(self, domain_size, n_elements, generator_type, filename, CNN_params=None):
        self.domain_length = domain_size[0]
        self.domain_height = domain_size[1]
        self.n_elements_x = n_elements[0]
        self.n_elements_y = n_elements[1]
        self.generator_type = generator_type
        self.filename = filename
        self.mesh_min = min(self.domain_length / self.n_elements_x, self.domain_height / self.n_elements_y)
        self.mesh_max = max(self.domain_length / self.n_elements_x, self.domain_height / self.n_elements_y)
        self.mesh_params = {'mesh_algorithm': 8, 'mesh_recombine': 1, 'mesh_element_order': 2}
        self.geo_generator = self.initialize_generator(generator_type, CNN_params)

        def initialize_generator(self, type, params):
            if type == 'CNN' and params is not None:
                # if CNN weights and biases are provided, we can initialize a CNN generator with those parameters
                return CNNGenerator(params)
            elif type == 'CNN':
                # if CNN weights and biases are not provided, we can initialize a default CNN generator
                return CNNGenerator()
            else:    
                # return a basic geometry generator
                return None
            
        def create_custom_hx(self, points):
            # create a custom hx obstruction in gmsh using the provided points
            n_points = len(points)
            gmsh_points = []
            for coord in points:
                point = gmsh.model.occ.addPoint(coord[0], coord[1], 0)
                gmsh_points.append(point)

            # Connect the points with lines to form the geometry of the obstruction
            lines = []
            for i in range(n_points):
                p1 = points[i]
                p2 = points[(i + 1) % n_points]  # Wrap around to connect the last point to the first
                line = gmsh.model.occ.addLine(p1, p2)
                lines.append(line)
            
            # create a surface from the lines
            cl = gmsh.model.occ.addCurveLoop(lines)
            surface = gmsh.model.occ.addPlaneSurface([cl])
            return surface
        
        def generate_mesh(self):
            # Initialize gmsh and create a new model
            gmsh.initialize()
            gmsh.model.add("heat_exchanger")

            # Use OpenCASCADE geometry kernel
            gmsh.model.occ

            # Define the domain geometry
            rect = gmsh.model.occ.addRectangle(0, -self.domain_height/2, 0, self.domain_length, self.domain_height)
            gmsh.model.occ.synchronize()

            # Add obstructions to the geometry based on the hx_objects provided by the generator
            obstructions = []
            for obj in self.hx_objects:
                obstruction = self.create_custom_hx(obj)
                obstructions.append(obstruction)
            gmsh.model.occ.synchronize()

            # Boolean cut
            cut = gmsh.model.occ.cut(
                [(2, rect)],
                [(2, s) for s in obstructions],
                removeObject=True,
                removeTool=True
            )
            gmsh.model.occ.synchronize()

            # Extract the resulting geometry after the cut operation
            outDimTags, _ = cut
            fluid_surfaces = [tag for dim, tag in outDimTags if dim == 2]

            if not fluid_surfaces:
                raise RuntimeError("Boolean cut resulted in no fluid domain. Please check the geometry of the obstructions.")
            
            gmsh.model.addPhysicalGroup(2, fluid_surfaces, name="Fluid")

            print("Cut result:", outDimTags)
            print("2D entities:", gmsh.model.getEntities(2))

            # Cylinder wall curves
            gmsh.model.occ.synchronize()
            boundaries = gmsh.model.getBoundary(
                [(2, s) for s in fluid_surfaces],
                oriented=False
            )

            obstruction_wall_curves = []
            inlet = []
            outlet = []
            top = []
            bottom = []

            for dim, tag in boundaries:
                com = gmsh.model.occ.getCenterOfMass(dim, tag)
                x, y, _ = com

                if abs(x) < 1e-6:
                    inlet.append(tag)
                elif abs(x - self.length) < 1e-6:
                    outlet.append(tag)
                elif abs(y - self.domain_height/2) < 1e-6:
                    top.append(tag)
                elif abs(y + self.domain_height/2) < 1e-6:
                    bottom.append(tag)
                else:
                    obstruction_wall_curves.append(tag)
            
            gmsh.model.addPhysicalGroup(1, obstruction_wall_curves, name="Wall")
            gmsh.model.addPhysicalGroup(1, inlet, name="Inlet")
            gmsh.model.addPhysicalGroup(1, outlet, name="Outlet")
            gmsh.model.addPhysicalGroup(1, top, name="Top")
            gmsh.model.addPhysicalGroup(1, bottom, name="Bottom")
            
            # Set mesh parameters
            gmsh.option.setNumber("Mesh.CharacteristicLengthMin", self.mesh_params['mesh_min'])
            gmsh.option.setNumber("Mesh.CharacteristicLengthMax", self.mesh_params['mesh_max'])
            gmsh.option.setNumber("Mesh.Algorithm", self.mesh_params['mesh_algorithm']) # 8 
            gmsh.option.setNumber("Mesh.RecombineAll", self.mesh_params['mesh_recombine']) # 1
            gmsh.option.setNumber("Mesh.ElementOrder", self.mesh_params['mesh_element_order']) # 2

            # Generate the mesh
            gmsh.model.mesh.generate(2)
            gmsh.write(self.filename)
            gmsh.finalize()