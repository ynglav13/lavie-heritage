const widget = document.getElementById('tutorial-widget');
const progressText = document.getElementById('progress-text');
const currentName = document.getElementById('current-name');
const currentDesc = document.getElementById('current-desc');

let currentStep = 1;
let totalSteps = 7;
let stepsData = [];

window.addEventListener('message', function(event)
{
    let data = event.data;

    if(data.action === "show")
    {
        widget.style.display = "flex";

        stepsData = data.steps;

        currentStep = data.currentStep;

        totalSteps = stepsData.length;

        updateWidget();
    }
    else if(data.action === "hide")
    {
        widget.style.display = "none";
    }
    else if(data.action === "update")
    {
        currentStep = data.currentStep;

        updateWidget();
    }
});

function updateWidget()
{
    if(currentStep > totalSteps)
    {
        widget.style.display = "none";
        return;
    }

    let stepInfo = stepsData[currentStep - 1];

    if(stepInfo)
    {
        currentName.innerText = stepInfo.name;
        
        if(stepInfo.desc)
        {
            currentDesc.innerText = stepInfo.desc;
            currentDesc.style.display = "block";
        }
        else
        {
            currentDesc.style.display = "none";
        }

        progressText.innerText = `(${currentStep}/${totalSteps})`;
    }
}
