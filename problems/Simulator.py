import subprocess

class Simulator:
    def __init__(self, type='MOOSE', params="./cutthroat-opt"):
        self.type = type
        if self.type == 'MOOSE':
            self.app_name = params
        else:
            pass
    
    def run_moose(self, input_file, n_processors=1):
        # Construct the command to run MOOSE
        cmd = [
            "conda", "run", "-n", "moose",
            "mpiexec", "-np", str(n_processors),
            self.app_name, "-i", input_file
        ]

        # Run the command
        result = subprocess.run(cmd, capture_output=True, text=True)

        # Check for errors
        if result.returncode != 0:
            print("Error running MOOSE:")
            print(result.stderr)
        else:
            print("MOOSE simulation completed successfully.")
            print(result.stdout)